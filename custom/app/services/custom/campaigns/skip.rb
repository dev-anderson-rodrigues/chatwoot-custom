# [FORK] Motivo de "pulado" do disparo em massa por qualquer caixa: o contato NAO recebe a mensagem e
# o destinatario e marcado `skipped` com este texto. Mostrado ao operador na tela de resultados,
# entao a mensagem tem de dizer o que fazer (vem de config/locales/fork.*.yml, no idioma da conta).
class Custom::Campaigns::Skip < StandardError; end
