terraform {
  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "0.34.0"
    }
    astra = {
      source = "datastax/astra"
      version = "2.1.0-rc9"
    }
  }
}

provider "snowflake" {
  alias = "sys_admin"
  role  = "SYSADMIN"
  region = "us-east-1"
}


