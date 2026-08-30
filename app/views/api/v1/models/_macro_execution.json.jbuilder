json.id execution.id
json.macro_id execution.macro_id
json.conversation_display_id execution.conversation&.display_id
json.status execution.status
json.inputs execution.inputs
json.error_message execution.error_message
json.actions_run execution.actions_run
json.actions_total execution.actions_total
json.created_at execution.created_at.to_i
json.updated_at execution.updated_at.to_i

if execution.user
  json.user do
    json.id execution.user.id
    json.name execution.user.name
    json.available_name execution.user.available_name
    json.avatar_url execution.user.avatar_url
  end
end
