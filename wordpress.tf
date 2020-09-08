provider "aws" {
  region = "us-east-2"
  profile = "aws-rds"

}


resource "aws_security_group" "rds-sg" {
  name        = "rds-sg"
  description = "Allow mysql inbound traffic"
  ingress{
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  

}



resource "aws_db_instance" "wordpressdb" {
  depends_on = [aws_security_group.rds-sg]
  allocated_storage = 20
  storage_type    = "gp2"
  engine    = "mysql"
  engine_version  = "5.7"
  instance_class  = "db.t2.micro"
  name      = "wordpressdb"
  username    = "wordpressuser"
  password    = "mysql15.7"
  parameter_group_name  = "default.mysql5.7"
  publicly_accessible = true
  skip_final_snapshot = true
  vpc_security_group_ids= [aws_security_group.rds-sg.id]
  tags = {
  name = "wordpres-mysql"
  }
}


#  --------------------  Wordpress Setup On K8s  ---------------------------------------------------
provider "kubernetes" {
  config_context = "minikube"
}

resource "kubernetes_namespace" "k8s-rds" {
  metadata {
    name = "k8s-rds"
  }
}

resource "kubernetes_persistent_volume_claim" "wordpress_pvc" {
  depends_on = [aws_db_instance.wordpressdb]
  metadata {
    name = "newwordpressclaim"
    namespace = kubernetes_namespace.k8s-rds.id
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
  

}



resource "kubernetes_deployment" "wordpress" {
  depends_on = [kubernetes_persistent_volume_claim.wordpress_pvc]
  metadata {
    name = "wordpress"
    namespace = kubernetes_namespace.k8s-rds.id
    labels = {
      Env = "wordpress"
    }
  }


  spec {
    replicas = 1
    selector {
      match_labels = {
        Env = "wordpress"
      }
    }


    template {
      metadata {
        labels = {
          Env = "wordpress"
        }
      }


      spec {
        container {
          name = "wordpress"
          image = "wordpress:4.8-apache"
          env{
            name = "WORDPRESS_DB_HOST"
            value = aws_db_instance.wordpressdb.address
          }
          env{
            name = "WORDPRESS_DB_USER"
            value = aws_db_instance.wordpressdb.username
          }
          env{
            name = "WORDPRESS_DB_PASSWORD"
            value = aws_db_instance.wordpressdb.password
          }
          env{
          name = "WORDPRESS_DB_NAME"
          value = aws_db_instance.wordpressdb.name
          }
          port {
            container_port = 80
          }
          volume_mount{
            name = "pv-wordpress"
            mount_path = "/var/lib/pam"
          }
        }
        volume{
          name = "pv-wordpress"
          persistent_volume_claim{
            claim_name = kubernetes_persistent_volume_claim.wordpress_pvc.metadata[0].name
          }
        }
      }
    }
  }
}


resource "kubernetes_service" "expose" {
  depends_on = [kubernetes_deployment.wordpress]
  metadata {
    name = "exposewp"
    namespace = kubernetes_namespace.k8s-rds.id
  }
  spec {


    selector = {
      Env = "${kubernetes_deployment.wordpress.metadata.0.labels.Env}"
    }
    port {
      node_port   = 32123
      port        = 80
      target_port = 80
    }
    type = "NodePort"
  }
}

