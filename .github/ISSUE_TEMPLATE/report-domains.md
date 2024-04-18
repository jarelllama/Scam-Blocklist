---
name: Report domain(s)
description: Please use this template to report domains so they can be properly incorporated with the workflows.
body:
  - type: textarea
    attributes:
      label: What domain(s) should be blocked?
      placeholder: |
        example.com
        http://example.com/index.php
    validations:
      required: true
  - type: textarea
    attributes:
      label: Please provide any additional information like reasons for blocking, etc. (optional)
      placeholder: |
        example.com
        http://example.com/index.php
---
