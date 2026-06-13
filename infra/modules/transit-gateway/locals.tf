locals {
  # Share via RAM only when caller passes account IDs; default is a private, unshared TGW.
  share_tgw = length(var.share_with_account_ids) > 0
}
