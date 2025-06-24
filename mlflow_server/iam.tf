data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { type = "Service" identifiers = ["ec2.amazonaws.com"] }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "mlflow-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_policy" "mlflow_s3" {
  name   = "mlflow-s3-policy"
  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [{
      Effect   : "Allow",
      Action   : ["s3:*"],
      Resource : [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_attach" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.mlflow_s3.arn
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "mlflow-ec2-profile"
  role = aws_iam_role.ec2.name
}