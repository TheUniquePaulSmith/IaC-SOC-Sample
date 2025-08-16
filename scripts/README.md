# Alternative Cloud-Init Script Examples

This folder contains different examples of how to handle cloud-init scripts in Terraform.

## 1. Basic External File (Recommended)

**File**: `cloud-init.yaml`
**Usage**: 
```hcl
locals {
  cloud_init_script = file("${path.module}/scripts/cloud-init.yaml")
}
```

**Pros**:
- Simple and clean
- Good for static content
- Easy to maintain

**Cons**:
- No variable substitution

## 2. Template File with Variables (Current Implementation)

**File**: `cloud-init.yaml`
**Usage**:
```hcl
locals {
  cloud_init_script = templatefile("${path.module}/scripts/cloud-init.yaml", {
    admin_username = var.admin_username
    custom_packages = var.additional_packages
  })
}
```

**Pros**:
- Variable substitution
- Dynamic content
- Flexible configuration

**Cons**:
- Slightly more complex

## 3. Multiple Script Files

You can have different cloud-init scripts for different purposes:

```hcl
locals {
  base_script = templatefile("${path.module}/scripts/base-setup.yaml", {
    admin_username = var.admin_username
  })
  
  security_script = templatefile("${path.module}/scripts/security-tools.yaml", {
    admin_username = var.admin_username
  })
  
  # Combine multiple scripts
  cloud_init_script = "${local.base_script}\n${local.security_script}"
}
```

## 4. Conditional Script Loading

```hcl
locals {
  cloud_init_script = var.install_security_tools ? 
    templatefile("${path.module}/scripts/full-soc.yaml", {
      admin_username = var.admin_username
    }) : 
    templatefile("${path.module}/scripts/basic.yaml", {
      admin_username = var.admin_username
    })
}
```

## 5. Script Validation

Add validation to ensure script files exist:

```hcl
variable "cloud_init_script_path" {
  description = "Path to the cloud-init script file"
  type        = string
  default     = "scripts/cloud-init.yaml"
  
  validation {
    condition     = fileexists("${path.module}/${var.cloud_init_script_path}")
    error_message = "The cloud-init script file does not exist at the specified path."
  }
}
```

## Template Variables Available

In your cloud-init template files, you can use these variables:
- `${admin_username}` - The VM administrator username
- `${region}` - Azure region (if passed)
- `${environment}` - Environment name (if passed)
- `${custom_packages}` - Additional packages to install

## Best Practices

1. **Keep scripts modular** - Separate concerns into different files
2. **Use meaningful names** - Name files based on their purpose
3. **Add comments** - Document what each section does
4. **Test scripts** - Test scripts independently before using in Terraform
5. **Version control** - Keep scripts in version control
6. **Validate syntax** - Use `cloud-init devel schema --config-file` to validate
