class Api::V1::Accounts::Conversations::CsatSurveysController < Api::V1::Accounts::Conversations::BaseController
  def create
    if @conversation.messages.where(content_type: :input_csat).present?
      render json: { error: 'CSAT already sent for this conversation' }, status: :unprocessable_entity
      return
    end

    CsatSurveyService.new(conversation: @conversation).perform(manual: true)
    head :ok
  end
end
