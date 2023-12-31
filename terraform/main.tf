terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }

    algolia = {
      source  = "k-yomo/algolia"
      version = ">= 0.1.0, < 1.0.0"
    }
  }

  required_version = ">= 1.2.0"
}

variable "ALGOLIA_APPID" { type = string }
variable "ALGOLIA_SECRET_KEY" { type = string }
variable "ALGOLIA_ADMIN_API_KEY" { type = string }
variable "RIOT_API_KEY" { type = string }
variable "AWS_REGION" { default = "eu-west-3" }

provider "aws" {
  region = var.AWS_REGION
}

provider "algolia" {
  app_id  = var.ALGOLIA_APPID
  api_key = var.ALGOLIA_ADMIN_API_KEY
}


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

data "archive_file" "tft_battler_get_challenger_function" {
  type        = "zip"
  source_file = "../get_data/get_challengers.py"
  output_path = "../tmp/tft_battler_get_challenger_function.zip"
}

data "archive_file" "tft_battler_get_matches_function" {
  type        = "zip"
  source_file = "../get_data/get_matches.py"
  output_path = "../tmp/tft_battler_get_matches_function.zip"
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
        "Action" : [
          "s3:PutObject",
          "s3:GetObject"
        ],
        "Resource" : "arn:aws:s3:::tft-battler/*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "athena:ListQueryExecutions",
          "athena:GetQueryResults",
          "athena:GetQueryExecution"
        ],
        "Resource" : [
          "*"
        ]
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
  handler          = "get_challengers.feed_dim_challengers"
  role             = aws_iam_role.tft_battler_lambda_role.arn
  filename         = data.archive_file.tft_battler_get_challenger_function.output_path
  source_code_hash = data.archive_file.tft_battler_get_challenger_function.output_base64sha256
  runtime          = "python3.10"
  timeout          = 600

  layers = [aws_lambda_layer_version.tft_battler_lambda_layer.arn]

  environment {
    variables = {
      /*db_username = aws_db_instance.TFT_Battler_DB.username
      db_password = aws_db_instance.TFT_Battler_DB.password
      db_endpoint = aws_db_instance.TFT_Battler_DB.endpoint*/
      AWS_S3_BUCKET      = aws_s3_bucket.tft_battler.id
      AWS_ATHENA_REGION  = var.AWS_REGION
      RIOT_API_KEY       = var.RIOT_API_KEY
      RIOT_REGION        = "euw1'"
      ALGOLIA_APPID      = var.ALGOLIA_APPID
      ALGOLIA_SECRET_KEY = var.ALGOLIA_SECRET_KEY
    }
  }
}

resource "aws_lambda_function" "TFT_Battler_Function_Get_Matches" {
  function_name    = "TFT_Battler_Get_Placements"
  handler          = "get_matches.feed_fact_placements"
  role             = aws_iam_role.tft_battler_lambda_role.arn
  filename         = data.archive_file.tft_battler_get_matches_function.output_path
  source_code_hash = data.archive_file.tft_battler_get_matches_function.output_base64sha256
  runtime          = "python3.10"
  timeout          = 900

  layers = [aws_lambda_layer_version.tft_battler_lambda_layer.arn]

  environment {
    variables = {
      /*db_username = aws_db_instance.TFT_Battler_DB.username
      db_password = aws_db_instance.TFT_Battler_DB.password
      db_endpoint = aws_db_instance.TFT_Battler_DB.endpoint*/
      AWS_S3_BUCKET      = aws_s3_bucket.tft_battler.id
      AWS_ATHENA_REGION  = var.AWS_REGION
      RIOT_API_KEY       = var.RIOT_API_KEY
      RIOT_REGION        = "euw1'"
      ALGOLIA_APPID      = var.ALGOLIA_APPID
      ALGOLIA_SECRET_KEY = var.ALGOLIA_SECRET_KEY
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
    path = "s3://${aws_s3_bucket.tft_battler.bucket}/db"
  }
}

resource "aws_athena_workgroup" "tft_battler" {
  name = "TFT_Battler"
}

resource "aws_athena_named_query" "tft_battler_athena_query" {
  name      = "TFT_Battler_GetAllChallergers_PUUID"
  workgroup = aws_athena_workgroup.tft_battler.id
  database  = aws_glue_catalog_database.tft_battler_catalog.name
  query     = "SELECT DISTINCT puuid FROM summoners;"
}

resource "aws_athena_named_query" "tft_battler_check_battle" {
  name      = "TFT_Battler_CheckChallengerBattle"
  workgroup = aws_athena_workgroup.tft_battler.id
  database  = aws_glue_catalog_database.tft_battler_catalog.name
  query     = <<EOT
                SELECT
                    match.matchid
                    , summoners_1.name player_1
                    , summoners_2.name player_2
                    , match.placement_player_1
                    , match.placement_player_2
                FROM (
                    SELECT
                        "matchid"
                        , COUNT(*) nb_participant
                        , MAX(CASE puuid WHEN  puuid_p1 THEN placement ELSE -1 END) placement_player_1
                        , MAX(CASE puuid WHEN  puuid_p2 THEN placement ELSE -1 END) placement_player_2
                        , MAX(puuid_p1) puuid_p1
                        , MAX(puuid_p2) puuid_p2
                    FROM (SELECT *, ? puuid_p1 , ? puuid_p2 FROM "match_placement")
                    WHERE (puuid = puuid_p1 OR puuid = puuid_p2)
                        AND (year = ? and month = ? AND day = ?)
                    GROUP BY matchid
                    HAVING COUNT(*) = 2) "match"
                LEFT JOIN  (SELECT puuid, MAX(name) name FROM summoners GROUP BY puuid) summoners_1 ON summoners_1.puuid = match.puuid_p1
                LEFT JOIN  (SELECT puuid, MAX(name) name FROM summoners GROUP BY puuid) summoners_2 ON summoners_2.puuid = match.puuid_p2
                EOT
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