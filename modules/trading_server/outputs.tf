# Trading Server Module Outputs

output "instance_info" {
  description = "Map of trading server instance information"
  value = {
    for key, instance in aws_instance.model_instance : key => {
      id         = instance.id
      public_ip  = instance.public_ip
      private_ip = instance.private_ip
      name       = instance.tags.Name
      model_type = instance.tags.ModelType
      symbol     = instance.tags.Symbol
      model_number = instance.tags.ModelNumber
    }
  }
}

output "s3_model_object_keys" {
  description = "List of S3 object keys under the models/ prefix"
  value       = data.aws_s3_objects.models.keys
}

output "matching_prefixes" {
  description = "Unique S3 prefixes matching the outer/inner pattern"
  value       = local.matching_prefixes
}

output "split_keys" {
  description = "Map of model information extracted from file prefixes"
  value       = local.split_keys
}

output "model_info_attrs" {
  description = "Map of model information extracted from file prefixes"
  value       = local.model_info_attrs
}