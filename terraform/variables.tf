variable "region" {
   type = string
   description = "Region to deploy all resources in"
}

variable "project" {
   type = string
   description = "Project to deploy all resources in"
}

variable "zone" {
   type = string
   description = "Zone to place instance in"
}

variable "api_key_sha256" {
   type = string
   description = "Sha256 has of api secret used in Authorization header to authorise requests"
}
