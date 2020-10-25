### Shared

resource "azurerm_resource_group" "rg" {
  name     = var.rg_name
  location = var.location
}

resource "azurerm_virtual_network" "default" {
  name                = "${var.prefix}-vnet"
  address_space       = ["10.0.0.0/8"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_route_table" "default" {
  name                = "${var.prefix}-route-table"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

### Azure Application Gateway

resource "azurerm_subnet" "agw" {
  name                 = "agw-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = ["10.1.0.0/24"]
}

#resource "azurerm_subnet_route_table_association" "agw" {
#  subnet_id      = azurerm_subnet.agw.id
#  route_table_id = azurerm_route_table.default.id
#}

resource "azurerm_public_ip" "agw" {
  name                = "${var.prefix}-agw-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "agw" {
  name                = "${var.prefix}-agw"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  enable_http2        = true

  sku {
    name     = var.agw_sku_name
    tier     = var.agw_sku_tier
    capacity = var.agw_sku_capacity
  }

  gateway_ip_configuration {
    name      = "${var.prefix}-agw-ip-config"
    subnet_id = azurerm_subnet.agw.id
  }

  frontend_ip_configuration {
    name                 = "fe-ip-config"
    public_ip_address_id = azurerm_public_ip.agw.id
  }

  frontend_port {
    name = "fe-port-80"
    port = 80
  }

  backend_address_pool {
    name = "default"
  }

  backend_http_settings {
    name                  = "default"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
  }

  http_listener {
    name                           = "default"
    frontend_ip_configuration_name = "fe-ip-config"
    frontend_port_name             = "fe-port-80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "default"
    rule_type                  = "Basic"
    http_listener_name         = "default"
    backend_address_pool_name  = "default"
    backend_http_settings_name = "default"
  }

  // Ignore most changes as they will be managed manually
  lifecycle {
    ignore_changes = [
      backend_address_pool,
      backend_http_settings,
      frontend_port,
      http_listener,
      probe,
      request_routing_rule,
      url_path_map
    ]
  }
}

### Azure Kubernetes Service

resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = ["10.240.0.0/16"]
}

#resource "azurerm_subnet_route_table_association" "aks" {
#  subnet_id      = azurerm_subnet.aks.id
#  route_table_id = azurerm_route_table.default.id
#}

resource "azurerm_role_assignment" "ra1" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = var.aks_sp_object_id

  depends_on = [azurerm_resource_group.rg]
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-k8s-cluster"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.prefix}-k8s-dns-prefix"

  default_node_pool {
    name           = "default"
    node_count     = var.k8s_node_count
    vm_size        = var.k8s_vm_size
    vnet_subnet_id = azurerm_subnet.aks.id
  }

  service_principal {
    client_id     = var.aks_sp_client_id
    client_secret = var.aks_sp_client_secret
  }

  network_profile {
    network_plugin = "azure"
  }

  role_based_access_control {
    enabled = true
  }
}
