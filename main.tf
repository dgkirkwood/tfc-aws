provider "aws" {
  region = "ap-southeast-2"
}


resource "aws_launch_configuration" "webserver" {
  image_id = "ami-02a599eb01e3b3c5b"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.instance.id]
  name_prefix = "worker-"

  user_data = <<-EOF
                #!/bin/bash
                echo "Hello Worldv2" > index.html
                nohup busybox httpd -f -p ${var.server_port} &
                EOF

    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_autoscaling_group" "webgroup" {
  launch_configuration = aws_launch_configuration.webserver.name
  vpc_zone_identifier = data.aws_subnet_ids.subnetcheck.ids

  name = aws_launch_configuration.webserver.name

  target_group_arns  = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"
  min_size = 3
  max_size = 3

  lifecycle {
      create_before_destroy = true
  }

  tag {
      key = "Name"
      value = "terraform-asg-example"
      propagate_at_launch  = true
  }
}

resource "aws_lb" "mylb" {
  name = "terraform-asg-example"
  load_balancer_type = "application"
  subnets = data.aws_subnet_ids.subnetcheck.ids
  security_groups = [aws_security_group.alb.id]
}


resource "aws_lb_listener" "http" {
  load_balancer_arn  = aws_lb.mylb.arn
  port = 80
  protocol = "HTTP"
  default_action {
      type = "fixed-response"
      fixed_response {
          content_type = "text/plain"
          message_body = "404: page not found"
          status_code = 404
      }
  }
}

resource "aws_lb_target_group" "asg" {
  name = "terraform-asg-example"
  port = var.server_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.defaultcheck.id
  health_check {
      path = "/"
      protocol = "HTTP"
      matcher = "200"
      interval = 15
      timeout = 3
      healthy_threshold = 2
      unhealthy_threshold = 2
    
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority = 100

  condition {
      field = "path-pattern"
      values = ["*"]
  }
  action {
      type = "forward"
      target_group_arn = aws_lb_target_group.asg.arn
  }
}



resource "aws_security_group" "instance" {
  name= "my-first-server-group"
  ingress {
      from_port = var.server_port
      to_port = var.server_port
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb" {
  name = "terraform-example-alb"

  ingress {
      from_port = 80
      to_port = 80
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_s3_bucket" "app_static_storage" {
  bucket = "dkirkwood-webapp-static"
  versioning {
      enabled = true
  }

  server_side_encryption_configuration {
      rule {
          apply_server_side_encryption_by_default {
              sse_algorithm = "AES256"
          }
      }
  }
}


data "aws_vpc" "defaultcheck" {
  default = true
}

data "aws_subnet_ids" "subnetcheck" {
  vpc_id = data.aws_vpc.defaultcheck.id
}



variable "server_port" {
  description = "the port the server will use for HTTP requests"
  type = number
}

output "alb_dns_name" {
  value = aws_lb.mylb.dns_name
  description = "The domain name of the load balancer"
}
