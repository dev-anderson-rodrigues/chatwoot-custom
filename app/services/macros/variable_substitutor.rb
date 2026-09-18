# Troca os tokens {{chave}} dos action_params da macro pelos valores que o
# agente preencheu nos input_fields no momento da execucao.
#
# Token desconhecido vira string vazia em vez de ficar literal na mensagem --
# melhor um trecho faltando do que mandar "{{cpf}}" para o cliente.
class Macros::VariableSubstitutor
  TOKEN_REGEX = /\{\{\s*([a-z][a-z0-9_]*)\s*\}\}/

  def initialize(inputs)
    @inputs = (inputs || {}).transform_keys(&:to_s)
  end

  def substitute_params(action_params)
    return action_params unless action_params.is_a?(Array)

    action_params.map { |param| substitute_value(param) }
  end

  private

  def substitute_value(value)
    return value unless value.is_a?(String)

    value.gsub(TOKEN_REGEX) { stringify(@inputs[Regexp.last_match(1)]) }
  end

  def stringify(value)
    return '' if value.nil?
    return value.join(', ') if value.is_a?(Array)

    value.to_s
  end
end
