# Exclude integration and send tests by default
# Run integration: mix test --include integration
# Run sends (careful!): mix test --include sends_message
ExUnit.start(exclude: [:integration, :sends_message])
