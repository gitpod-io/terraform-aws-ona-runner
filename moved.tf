moved {
  from = aws_lb.proxy
  to   = aws_lb.proxy[0]
}

moved {
  from = aws_lb_target_group.proxy
  to   = aws_lb_target_group.proxy[0]
}

moved {
  from = aws_lb_listener.proxy_tls
  to   = aws_lb_listener.proxy_tls[0]
}

moved {
  from = aws_cloudwatch_log_group.proxy
  to   = aws_cloudwatch_log_group.proxy[0]
}

moved {
  from = aws_ecs_task_definition.proxy
  to   = aws_ecs_task_definition.proxy[0]
}

moved {
  from = aws_ecs_service.proxy
  to   = aws_ecs_service.proxy[0]
}

moved {
  from = aws_appautoscaling_target.proxy
  to   = aws_appautoscaling_target.proxy[0]
}

moved {
  from = aws_appautoscaling_policy.proxy_cpu
  to   = aws_appautoscaling_policy.proxy_cpu[0]
}

moved {
  from = aws_appautoscaling_policy.proxy_memory
  to   = aws_appautoscaling_policy.proxy_memory[0]
}

moved {
  from = aws_iam_role.proxy
  to   = aws_iam_role.proxy[0]
}

moved {
  from = aws_iam_role_policy.proxy
  to   = aws_iam_role_policy.proxy[0]
}

moved {
  from = aws_iam_policy.proxy_boundary
  to   = aws_iam_policy.proxy_boundary[0]
}

moved {
  from = aws_security_group_rule.ecs_from_load_balancer
  to   = aws_security_group_rule.ecs_from_load_balancer[0]
}

moved {
  from = aws_security_group_rule.ecs_portspec_self
  to   = aws_security_group_rule.ecs_portspec_self[0]
}

moved {
  from = aws_security_group_rule.ecs_runner_api_self
  to   = aws_security_group_rule.ecs_runner_api_self[0]
}

moved {
  from = aws_security_group_rule.ecs_proxy_metrics_self
  to   = aws_security_group_rule.ecs_proxy_metrics_self[0]
}
