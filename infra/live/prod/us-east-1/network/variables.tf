variable "name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "az_subnets" {
  type = map(object({
    public  = string
    private = string
    intra   = string
  }))
}
