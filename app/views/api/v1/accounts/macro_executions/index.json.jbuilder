json.meta do
  json.total @total_count
end

json.payload do
  json.array! @executions do |execution|
    json.partial! 'api/v1/models/macro_execution', formats: [:json], execution: execution
  end
end
