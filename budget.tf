# Chunk 0 cost guardrail: a low-threshold subscription budget. The day-one
# backstop against a forgotten running VM. Alerts at 80% actual + 100% forecast.
resource "azurerm_consumption_budget_subscription" "poc0" {
  name            = "budget-${var.name_prefix}-poc0"
  subscription_id = "/subscriptions/${var.subscription_id}"

  amount     = var.budget_amount
  time_grain = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = [var.budget_alert_email]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = [var.budget_alert_email]
  }

  # Budgets live under Microsoft.Consumption — make the RP registration explicit.
  depends_on = [azurerm_resource_provider_registration.consumption]
}
