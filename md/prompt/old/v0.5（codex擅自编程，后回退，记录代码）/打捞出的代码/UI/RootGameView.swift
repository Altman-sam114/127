        }
        .background(Color(.systemBackground))
    }
            )
            EventLogView(entries: container.displayEventLog)
            AgentPanelView()
        }
    }
                case .agent:
                    AgentPanelView()
                }
            }
