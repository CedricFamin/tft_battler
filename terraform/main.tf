terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
    
    algolia = {
      source = "k-yomo/algolia"
      version = ">= 0.1.0, < 1.0.0"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "eu-west-3"
}

variable "RIOT_API_KEY" { type = string }

resource "aws_s3_bucket" "tft_battler" {
  bucket = "tft-battler"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "TFT_Battler"
    Environment = "Prod"
  }
}

/*resource "aws_db_instance" "TFT_Battler_DB" {
  allocated_storage    = 10
  db_name              = "TFTBattler"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.micro"
  username             = "foo"
  password             = "foobarbaz"
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
}*/

data "archive_file" "tft_battler_lambda_function" {
  type        = "zip"
  source_file = "../main.py"
  output_path = "../tmp/lambda_function.zip"
}

resource "aws_iam_role" "tft_battler_lambda_role" {
  name = "TFT_Battler_Lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
        ]
        Effect = "Allow"
        Principal : {
          Service : [
            "lambda.amazonaws.com"
          ]
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "TFT_Battler_Lambda_Policy"
  description = ""
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : "s3:PutObject",
        "Resource" : "arn:aws:s3:::tft-battler/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "test-attach" {
  role       = aws_iam_role.tft_battler_lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

data "archive_file" "tft_battler_lambda_layer_files" {
  type        = "zip"
  source_dir  = "../lambda_layer"
  output_path = "../tmp/lambda_layer.zip"
}

resource "aws_lambda_layer_version" "tft_battler_lambda_layer" {
  filename         = data.archive_file.tft_battler_lambda_layer_files.output_path
  source_code_hash = data.archive_file.tft_battler_lambda_layer_files.output_base64sha256
  layer_name       = "TFT_Battler_Lambda_Layer"

  compatible_runtimes = ["python3.10"]
}

resource "aws_lambda_function" "TFT_Battler_Function_Get_Challengers" {
  function_name    = "TFT_Battler_Get_Challengers"
  handler          = "main.feed_dim_challengers"
  role             = aws_iam_role.tft_battler_lambda_role.arn
  filename         = data.archive_file.tft_battler_lambda_function.output_path
  source_code_hash = data.archive_file.tft_battler_lambda_function.output_base64sha256
  runtime          = "python3.10"
  timeout          = 600

  layers = [aws_lambda_layer_version.tft_battler_lambda_layer.arn]

  environment {
    variables = {
      /*db_username = aws_db_instance.TFT_Battler_DB.username
      db_password = aws_db_instance.TFT_Battler_DB.password
      db_endpoint = aws_db_instance.TFT_Battler_DB.endpoint*/
      S3_BUCKET = aws_s3_bucket.tft_battler.id
      RIOT_API_KEY = var.RIOT_API_KEY
    }
  }
}

resource "aws_lambda_function" "TFT_Battler_Function_Get_Matches" {
  function_name    = "TFT_Battler_Get_Placements"
  handler          = "main.feed_fact_placements"
  role             = aws_iam_role.tft_battler_lambda_role.arn
  filename         = data.archive_file.tft_battler_lambda_function.output_path
  source_code_hash = data.archive_file.tft_battler_lambda_function.output_base64sha256
  runtime          = "python3.10"
  timeout          = 600

  layers = [aws_lambda_layer_version.tft_battler_lambda_layer.arn]

  environment {
    variables = {
      /*db_username = aws_db_instance.TFT_Battler_DB.username
      db_password = aws_db_instance.TFT_Battler_DB.password
      db_endpoint = aws_db_instance.TFT_Battler_DB.endpoint*/
      S3_BUCKET = aws_s3_bucket.tft_battler.id
      RIOT_API_KEY = var.RIOT_API_KEY
    }
  }
}

resource "aws_glue_catalog_database" "tft_battler_catalog" {
  name = "tft-battler-catalog"
}

resource "aws_iam_role" "tft_battler_glue_role" {
  name = "TFT_Battler_Glue"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole"
        ]
        Effect = "Allow"
        Principal : {
          Service : [
            "glue.amazonaws.com"
          ]
        }
      }
    ]
  })
}

resource "aws_iam_policy" "crawler_policy" {
  name        = "TFT_Battler_Crawler_Policy"
  description = ""
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:Get*",
          "s3:List*",
          "s3:*Object*",
        ]
        "Resource" : [
          "arn:aws:s3:::tft-battler/*",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "crawler_policy_attach" {
  role = aws_iam_role.tft_battler_glue_role.name

  for_each = toset([

    aws_iam_policy.crawler_policy.arn,
    "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
  ])
  policy_arn = each.value
}

resource "aws_glue_crawler" "tft_battler_crawler_s3" {
  database_name = aws_glue_catalog_database.tft_battler_catalog.name
  name          = "tft-battler-crawler-s3"
  role          = aws_iam_role.tft_battler_glue_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.tft_battler.bucket}"
  }
}

resource "aws_athena_workgroup" "tft_battler" {
  name = "TFT_Battler"
}

resource "aws_athena_named_query" "tft_battler_athena_query" {
  name      = "TFT_Battler_GetAllChallergers_PUUID"
  workgroup = aws_athena_workgroup.tft_battler.id
  database  = "${aws_glue_catalog_database.tft_battler_catalog.name}"
  query     = "SELECT DISTINCT puuid FROM tft_battler;"
}

provider "algolia" {
  app_id = "RRFZXCCV6H"
}

resource "algolia_index" "tft_battler" {
  name = "tft_battler"

  attributes_config {
    searchable_attributes = [
      "name"
    ]
    attributes_to_retrieve = [
        "name"
      , "id"
      , "puuid"
      , "accountid"
      , "profileIconId"
      , "revisionDate"
      , "summonerLevel"
    ]
  }
}