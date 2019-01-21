###

# front

###

resource "aws_security_group" "front" {
  name        = "${var.project}-front-${var.env}"
  description = "Front ${var.env} for ${var.project}"
  vpc_id      = "${var.vpc_id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    cycloid.io = "true"
    Name       = "${var.project}-front-${var.env}"
    env        = "${var.env}"
    project    = "${var.project}"
    role       = "front"
  }
}

resource "aws_security_group_rule" "elb_to_front_http" {
  type                     = "ingress"
  from_port                = "80"
  to_port                  = "80"
  protocol                 = "tcp"
  source_security_group_id = "${aws_security_group.elb-front.id}"
  security_group_id        = "${aws_security_group.front.id}"
}

resource "aws_security_group_rule" "bastion_to_front_ssh" {
  count                    = "${var.bastion_sg_allow != "" ? 1 : 0}"
  type                     = "ingress"
  from_port                = "22"
  to_port                  = "22"
  protocol                 = "tcp"
  source_security_group_id = "${var.bastion_sg_allow}"
  security_group_id        = "${aws_security_group.front.id}"
}

###

# EC2

###

resource "aws_instance" "front" {
  ami = "${data.aws_ami.debian_jessie.id}"

  # associate_public_ip_address = false
  count                = "${var.front_count}"
  iam_instance_profile = "${aws_iam_instance_profile.front_profile.name}"
  instance_type        = "${var.front_type}"
  key_name             = "${var.keypair_name}"
  ebs_optimized        = "${var.front_ebs_optimized}"

  vpc_security_group_ids = ["${compact(list(
    "${var.bastion_sg_allow}",
    "${aws_security_group.front.id}",
  ))}"]

  subnet_id = "${element(var.private_subnets_ids, count.index)}"

  root_block_device {
    volume_size           = "${var.front_disk_size}"
    volume_type           = "${var.front_disk_type}"
    delete_on_termination = true
  }

  volume_tags {
    cycloid.io = "true"
    Name       = "${var.project}-front${count.index}-${lookup(var.short_region, var.aws_region)}-${var.env}"
    env        = "${var.env}"
    project    = "${var.project}"
    role       = "front"
  }

  tags {
    cycloid.io = "true"
    Name       = "${var.project}-front${count.index}-${lookup(var.short_region, var.aws_region)}-${var.env}"
    env        = "${var.env}"
    project    = "${var.project}"
    role       = "front"
  }
}

###

# ELB

###

resource "aws_security_group" "elb-front" {
  name        = "${var.project}-elb-front-${var.env}"
  description = "Front ${var.env} for ${var.project}"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    cycloid.io = "true"
    Name       = "${var.project}-elb-front-${var.env}"
    env        = "${var.env}"
    project    = "${var.project}"
  }
}

###

# Create a loadbalancer for the fronts

###

resource "aws_elb" "front" {
  name = "${var.project}-front-${var.env}"

  listener {
    lb_port           = 80
    lb_protocol       = "tcp"
    instance_port     = 80
    instance_protocol = "tcp"
  }

  listener {
    lb_port            = 443
    lb_protocol        = "https"
    instance_port      = 80
    instance_protocol  = "http"
    ssl_certificate_id = "${var.magento_ssl_cert}"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "TCP:80"
    interval            = 30
  }

  security_groups           = ["${aws_security_group.elb-front.id}"]
  subnets                   = ["${var.public_subnets_ids}"]
  instances                 = ["${aws_instance.front.*.id}"]
  internal                  = false
  cross_zone_load_balancing = true
  idle_timeout              = 120

  tags {
    cycloid.io = "true"
    Name       = "${var.project}-front-${lookup(var.short_region, var.aws_region)}-${var.env}"
    role       = "front"
    env        = "${var.env}"
    project    = "${var.project}"
  }
}

###

# Cloudwatch Alarms

###

resource "aws_cloudwatch_metric_alarm" "recover-front" {
  alarm_actions       = ["arn:aws:automate:${var.aws_region}:ec2:recover"]
  alarm_description   = "Recover the instance"
  alarm_name          = "cycloid-engine_recover-${var.project}-front${count.index}-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  count               = "${var.front_count}"

  dimensions = {
    InstanceId = "${element(aws_instance.front.*.id, count.index)}"
  }

  evaluation_periods        = "2"
  insufficient_data_actions = []
  metric_name               = "StatusCheckFailed_System"
  namespace                 = "AWS/EC2"
  period                    = "60"
  statistic                 = "Average"
  threshold                 = "0"
}
