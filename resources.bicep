param name string
param location string
param resourceToken string
param tags object

var prefix = '${name}-${resourceToken}'
@description('Port of the Redis Enterprise Cache')
param redisPort int = 10000
//added for Redis Cache
var cacheServerName = '${prefix}-redisCache'
//added for Redis Cache
var cacheSubnetName = 'cache-subnet'
//added for Redis Cache
var cachePrivateEndpointName = 'cache-privateEndpoint'
//added for Redis Cache
var cachePvtEndpointDnsGroupName = 'cacheDnsGroup'
//added for user assigned identity
var userAssignedIdentity = '${prefix}-userAssignedIdentity'
//added for Key Vault that contains key for CMK
var keyVaultName = 'kv${resourceToken}'
//added for encryption key in Key Vault that's used for CMK
var keyName = '${prefix}-key'
//added for key vault 
var keyvaultPvtEndpointName = 'keyvault-privateEndpoint'
//added for key vault
var keyvaultSubnetName = 'keyvault-subnet'
//added for key vault
var keyvaultPvtEndpointDnsGroupName = 'keyvaultDnsGroup'


resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: '${prefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: cacheSubnetName
        properties:{
          addressPrefix: '10.0.2.0/24'
        }
      }
      {
        name: keyvaultSubnetName
        properties:{
          addressPrefix: '10.0.1.0/24'
        }
      }
    ]
  }
  //added for Redis Cache
  resource cacheSubnet 'subnets' existing = {
    name: cacheSubnetName
  }
  //added for Key Vault
  resource keyvaultSubnet 'subnets' existing = {
    name: keyvaultSubnetName
  }
}


// added for Redis Cache
resource privateDnsZoneCache 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.redisenterprise.cache.azure.net'
  location: 'global'
  tags: tags
  dependsOn:[
    virtualNetwork
  ]
}
// added for Key Vault
resource privateDnsZoneKeyVault 'Microsoft.Network/privateDnsZones@2020-06-01'={
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
  dependsOn:[
    virtualNetwork
  ]
}

 //added for Redis Cache
resource privateDnsZoneLinkCache 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
 parent: privateDnsZoneCache
 name: 'privatelink.redisenterprise.cache.azure.net-applink'
 location: 'global'
 properties: {
   registrationEnabled: false
   virtualNetwork: {
     id: virtualNetwork.id
   }
 }
}

//added for Key Vault
resource privateDnsZoneLinkKeyVault 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01'={
  parent: privateDnsZoneKeyVault
  name: 'privatelink.vaultcore.azure.net-applink'
  location: 'global'
 properties: {
   registrationEnabled: false
   virtualNetwork: {
     id: virtualNetwork.id
   }
 }
}

resource cachePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: cachePrivateEndpointName
  location: location
  properties: {
    subnet: {
      id: virtualNetwork::cacheSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: cachePrivateEndpointName
        properties: {
          privateLinkServiceId: redisCache.id
          groupIds: [
            'redisEnterprise'
          ]
        }
      }
    ]
  }
  resource cachePvtEndpointDnsGroup 'privateDnsZoneGroups' = {
    name: cachePvtEndpointDnsGroupName
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'privatelink-redisenterprise-cache-azure-net'
          properties: {
            privateDnsZoneId: privateDnsZoneCache.id
          }
        }
      ]
    }
  }
}

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: keyvaultPvtEndpointName
  location: location
  properties:{
    subnet: {
      id: virtualNetwork::keyvaultSubnet.id
    }
    privateLinkServiceConnections:[
      {
        name: keyvaultPvtEndpointName
        properties:{
          privateLinkServiceId: keyVault.id
          groupIds:[
            'vault'
          ]
        }
      }
    ]
  }
  resource keyvaultPvtEndpointDnsGroup 'privateDnsZoneGroups' = {
    name: keyvaultPvtEndpointDnsGroupName
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'privatelink-vaultcore-azure-net'
          properties:{
            privateDnsZoneId: privateDnsZoneCache.id
          }
        }
      ]
    }
  }
}

//added for Redis Cache
resource redisCache 'Microsoft.Cache/redisEnterprise@2023-11-01' = {
  location: location
  name: cacheServerName
  sku:{
    capacity:2
    name:'Enterprise_E10'
  }
  //identity:{
  //  type:'UserAssigned'
  //  userAssignedIdentities: {
  //    '${managedIdentity.id}': {}
  //  }
  //}
  //properties:{
  //  encryption:{
  //    customerManagedKeyEncryption:{
  //      keyEncryptionKeyIdentity:{
  //        identityType: 'userAssignedIdentity'
  //        userAssignedIdentityResourceId:managedIdentity.id
  //      }
  //      keyEncryptionKeyUrl: encryptionKey.properties.keyUriWithVersion
  //    }
  //  }
  //}
  dependsOn:[keyVault]
}

resource redisdatabase 'Microsoft.Cache/redisEnterprise/databases@2022-01-01' = {
  name: 'default'
  parent: redisCache
  properties: {
    evictionPolicy:'NoEviction'
    clusteringPolicy: 'EnterpriseCluster'
    modules: [
      {
        name: 'RediSearch'
      }
      {
        name: 'RedisJSON'
      }
    ]
    port: redisPort
  }
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31'={
  location: location
  name:userAssignedIdentity
  tags:tags
}



resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  location:location
  name:keyVaultName
  tags: tags
  properties:{
    sku:{
      family:'A'
      name:'premium'
    }
    tenantId: subscription().tenantId
    accessPolicies:[
      {
        applicationId: managedIdentity.properties.clientId
        objectId: managedIdentity.properties.principalId
        permissions: {
          keys: [
            'get'
            'wrapKey'
            'unwrapKey'
          ]
        }
        tenantId: subscription().tenantId
      }]
      enablePurgeProtection: true
  }
}

resource encryptionKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' = {
  name: keyName
  tags: tags
  parent:keyVault
  properties:{
    attributes: {
      enabled: true
      exportable: false
      nbf: 0
    }
    keySize: 2048
    kty: 'RSA-HSM'
  }
}
