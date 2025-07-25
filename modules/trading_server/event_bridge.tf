###############################################################################
# (A) Allow AlpacaWebsocketLambda's execution role to invoke TradingServerLambda (conditional)
###############################################################################

resource "aws_iam_role_policy" "alpaca_websocket_invoke_trading_policy" {
  count = var.enable_eventbridge ? 1 : 0
  
  name = "alpaca-websocket-invoke-trading-${var.environment}"
  role = aws_iam_role.lambda_role.id   # this is the role for AlpacaWebsocketLambda

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.trading_server_lambda.arn
      }
    ]
  })
}

#################################################################
# (B) Chain: when AlpacaWebsocketLambda async invocation succeeds
#      → invoke TradingServerLambda (conditional)
#################################################################

resource "aws_lambda_function_event_invoke_config" "chain_alpaca_to_trading" {
  count = var.enable_eventbridge ? 1 : 0
  
  function_name = "AlpacaWebsocketLambda_${var.environment}"

  # optional: keep failed events for 1h, never retry
  maximum_event_age_in_seconds = 3600
  maximum_retry_attempts       = 0

  destination_config {
    on_success {
      destination = aws_lambda_function.trading_server_lambda.arn
    }
    # on_failure { 
    #   destination = "arn:aws:sns:…"
    # }  # if you want to capture errors
  }
}