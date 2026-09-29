# [FORK] Ritmo entre envios das campanhas em massa.
#
# Configuravel por ambiente (padrao conservador):
#   CAMPAIGN_SEND_INTERVAL_MS   pausa entre envios (padrao 300 => ~3 msg/s)
#
# No WhatsApp a pausa protege o limite de vazao do provider; nas caixas do disparo generico
# (Custom::Campaigns::OneoffMessageService) protege a fila `high` do Sidekiq, que e a mesma
# em que os agentes enviam as respostas: sem pausa, uma campanha de milhares de contatos
# enfileira todos os envios de uma vez e atrasa o atendimento.
module Custom::Campaigns::SendPacing
  private

  def send_interval
    ENV.fetch('CAMPAIGN_SEND_INTERVAL_MS', 300).to_f / 1000
  end

  # Metodo proprio (e nao `sleep` solto) para os specs poderem trocar.
  def pause(seconds)
    sleep(seconds) if seconds.to_f.positive?
  end
end
