resource "snowflake_database" "testdb" {
  provider = snowflake.sys_admin
  name     = "ASTRA_DEMO2"
}

resource "snowflake_warehouse" "testwarehouse" {
  provider       = snowflake.sys_admin
  name           = "ASTRA_DEMO2"
  warehouse_size = "xsmall"

  auto_suspend = 60
}

resource "snowflake_schema" "testschema" {
  provider   = snowflake.sys_admin
  database   = snowflake_database.testdb.name
  name       = "ASTRA_DEMO2"
  is_managed = false
}

resource "astra_streaming_tenant" "streaming_tenant_snowflake" {
  tenant_name        = "terraformsnowflakeaws"
  topic              = "terraformtest"
  region             = "us-east-1"
  cloud_provider     = "aws"
  user_email         = "seb@datastax.com"
}

resource "astra_database" "dev" {
  name           = "puppies"
  keyspace       = "puppies"
  cloud_provider = "aws"
  regions        = ["us-east-1"]
}

resource "astra_table" "table1" {
  depends_on            = [ astra_database.dev ]
  table                 = "mytable"
  keyspace              = astra_database.dev.keyspace
  database_id           = astra_database.dev.id
  region                = "us-east-1"
  clustering_columns    = "a"
  partition_keys        = "b"
  column_definitions= [
    {
      Name: "a"
      Static: false
      TypeDefinition: "text"
    },
    {
      Name: "b"
      Static: false
      TypeDefinition: "text"
    }
  ]
}

resource "astra_cdc" "cdc1" {
  depends_on            = [ snowflake_database.testdb, snowflake_schema.testschema, astra_streaming_tenant.streaming_tenant_snowflake, astra_table.table1 ]
  database_id           = astra_database.dev.id
  database_name         = astra_database.dev.name
  table                 = astra_table.table1.table
  keyspace              = astra_table.table1.keyspace
  topic_partitions      = 3
  tenant_name           = astra_streaming_tenant.streaming_tenant_snowflake.tenant_name
}
resource "astra_streaming_topic" "offset_topic" {
  depends_on         = [ astra_streaming_tenant.streaming_tenant_snowflake ]
  topic              = "offset"
  tenant_name        = astra_streaming_tenant.streaming_tenant_snowflake.tenant_name
  region             = astra_streaming_tenant.streaming_tenant_snowflake.region
  cloud_provider     = astra_streaming_tenant.streaming_tenant_snowflake.cloud_provider
  namespace          = "default"
}
resource "astra_streaming_sink" "streaming_sink-1" { 
  depends_on            = [ astra_streaming_tenant.streaming_tenant_snowflake, astra_cdc.cdc1, astra_streaming_topic.offset_topic ]
  tenant_name           = astra_streaming_tenant.streaming_tenant_snowflake.tenant_name
  topic                 = astra_cdc.cdc1.data_topic
  region                = astra_streaming_tenant.streaming_tenant_snowflake.region
  cloud_provider        = astra_streaming_tenant.streaming_tenant_snowflake.cloud_provider
  sink_name             = "snowflake" 
  retain_ordering       = true 
  processing_guarantees = "ATLEAST_ONCE" 
  parallelism           = 3 
  namespace             = "astracdc" 
  auto_ack              = true
  sink_configs          = jsonencode({ 
    "lingerTimeMs": "10",
    "batchSize": "10",
    "topic": replace(astra_cdc.cdc1.data_topic, "persistent://",""), 
    "offsetStorageTopic": format("%s/%s/%s",astra_streaming_tenant.streaming_tenant_snowflake.tenant_name, astra_streaming_topic.offset_topic.namespace, astra_streaming_topic.offset_topic.topic), 
    "kafkaConnectorConfigProperties": {
      "connector.class": "com.snowflake.kafka.connector.SnowflakeSinkConnector",
      "key.converter": "org.apache.kafka.connect.storage.StringConverter",
      "name": "snowflake",
      "snowflake.database.name": snowflake_database.testdb.name,
      "snowflake.private.key": var.snowflake_key
      "snowflake.schema.name": snowflake_schema.testschema.name,
      "snowflake.url.name": "https://REDACTED-ACCOUNT.us-east-1.snowflakecomputing.com",
      "snowflake.user.name": "tf-snow",
      "value.converter": "com.snowflake.kafka.connector.records.SnowflakeJsonConverter",
      "topic": replace(astra_cdc.cdc1.data_topic, "persistent://",""), 
      "buffer.flush.time": 10,
      "buffer.count.records": 10,
      "buffer.size.bytes": 10
    }
 })
}
