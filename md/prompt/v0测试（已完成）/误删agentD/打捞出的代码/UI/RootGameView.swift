        Group {
            if horizontalSizeClass == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .background(Color(.systemBackground))
        .task {
            container.runAIIfNeeded()
        }
            EventLogView(entries: container.displayEventLog)
            AgentPanelView(record: container.lastAgentDecisionRecord)
        }
    }
                case .agent:
                    AgentPanelView(record: container.lastAgentDecisionRecord)
                }
            }
