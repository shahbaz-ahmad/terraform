variable "subscription_id" {}
variable "tenant_id" {}
variable "client_id" {}
variable "client_secret" {}

variable "web_server_location" {}
variable "web_server_rg" {}
variable "resource_prefix" {}
variable "web_server_address_space" {}
variable "web_server_subnets" {
    type = list
}
variable "web_server_name" {}
variable "environment" {}
variable "web_server_count" {}
variable "domain_name_label" {}

provider "azurerm" {
    version = "~>2.0"
    features{}
    client_id = var.client_id
    tenant_id = var.tenant_id
    client_secret = var.client_secret
    subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "web_server_rg" {
    name = var.web_server_rg
    location = var.web_server_location
}

resource "azurerm_virtual_network" "web_server_vnet"{
    name = "${var.resource_prefix}-vnet"
    location = var.web_server_location
    resource_group_name = azurerm_resource_group.web_server_rg.name
    address_space = ["${var.web_server_address_space}"]
}

resource "azurerm_subnet" "web_server_subnet" {
    name = "${var.resource_prefix}-${substr(var.web_server_subnets[count.index], 0, length(var.web_server_subnets[count.index])-3)}-subnet"
    resource_group_name = azurerm_resource_group.web_server_rg.name
    virtual_network_name = azurerm_virtual_network.web_server_vnet.name    
    #address_prefixes = ["1.0.1.0/24","1.0.2.0/24"] #"${var.web_server_subnets}" #this doesn't work
    address_prefix = "${var.web_server_subnets[count.index]}"
    count = length(var.web_server_subnets)
}

resource "azurerm_public_ip" "web_server_lb_pip" {     
    name = "${var.resource_prefix}-pip"    
    location = var.web_server_location
    resource_group_name = azurerm_resource_group.web_server_rg.name
    allocation_method = var.environment == "production" ? "Static" : "Dynamic"    
    domain_name_label = var.domain_name_label
}

resource "azurerm_network_security_group" "web_server_nsg" {
    name = "${var.resource_prefix}-nsg"    
    location = var.web_server_location
    resource_group_name = azurerm_resource_group.web_server_rg.name

    security_rule {
        name = "HTTP"
        priority = 1001
        direction = "Inbound"
        access = "Allow"
        protocol = "Tcp"
        source_port_range = "*"
        destination_port_range = "80"
        source_address_prefix = "*"
        destination_address_prefix = "*"
    }
}

resource "azurerm_subnet_network_security_group_association" "web_server_nsg_association" {
    network_security_group_id = azurerm_network_security_group.web_server_nsg.id
    subnet_id = azurerm_subnet.web_server_subnet.*.id[0]
    #count = length(var.web_server_subnets)
}


resource "azurerm_windows_virtual_machine_scale_set" "web_server" {    
    name = "${var.web_server_name}-scale-set"
    location = var.web_server_location
    resource_group_name = azurerm_resource_group.web_server_rg.name
    upgrade_mode = "Manual"
    computer_name_prefix = var.web_server_name
    admin_username = "shahbaz"
    admin_password = "K1daKadonKithay!"

    sku = "Standard_B1s"
    instances = var.web_server_count
    
    source_image_reference {
        publisher = "MicrosoftWindowsServer"
        offer = "WindowsServer"
        sku = "2016-Datacenter-Server-Core-smalldisk"
        version = "latest"
    }

    os_disk {        
        caching = "ReadWrite"
        storage_account_type = "Standard_LRS"
    }

    network_interface {
        name = "web_server_network_profile"
        primary = true
        ip_configuration {
          name = var.web_server_name
          primary = true
          subnet_id = azurerm_subnet.web_server_subnet.*.id[0]
          load_balancer_backend_address_pool_ids = ["${azurerm_lb_backend_address_pool.web_server_lb_backend_pool.id}"]
        }
    }
}

resource "azurerm_lb" "web_server_lb" {
    name = "${var.resource_prefix}-lb"    
    location = var.web_server_location
    resource_group_name = azurerm_resource_group.web_server_rg.name
    frontend_ip_configuration {
        name = "${var.resource_prefix}-lb-frontend-ip"
        public_ip_address_id = azurerm_public_ip.web_server_lb_pip.id        
    }    
}

resource "azurerm_lb_backend_address_pool" "web_server_lb_backend_pool" {
    name = "${var.resource_prefix}-lb-backend-pool"        
    resource_group_name = azurerm_resource_group.web_server_rg.name
    loadbalancer_id = azurerm_lb.web_server_lb.id
}

resource "azurerm_lb_probe" "web_server_lb_http_probe" {
    name = "${var.resource_prefix}-lb-https-probe"        
    resource_group_name = azurerm_resource_group.web_server_rg.name
    loadbalancer_id = azurerm_lb.web_server_lb.id    
    protocol = "Tcp"
    port = "80"
}

resource "azurerm_lb_rule" "web_server_lb_http_rule" {
    name = "${var.resource_prefix}-lb-backend-pool-rule"        
    resource_group_name = azurerm_resource_group.web_server_rg.name
    loadbalancer_id = azurerm_lb.web_server_lb.id
    protocol = "Tcp"
    frontend_port = "80"
    backend_port = "80"
    frontend_ip_configuration_name = "${var.resource_prefix}-lb-frontend-ip"
    probe_id = azurerm_lb_probe.web_server_lb_http_probe.id
    backend_address_pool_id = azurerm_lb_backend_address_pool.web_server_lb_backend_pool.id
}