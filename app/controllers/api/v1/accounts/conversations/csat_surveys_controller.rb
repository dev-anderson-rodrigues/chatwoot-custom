class Api::V1::Accounts::Conversations::CsatSurveysController < Api::V1::Accounts::Conversations::BaseController
  def create
    unless @conversation.resolved?
      render json: { error: 'Conversation must be resolved before sending CSAT' }, status: :unprocessable_entity
      return
    end

    if @conversation.messages.where(content_type: :input_csat).present?
      render json: { error: 'CSAT already sent for this conversation' }, status: :unprocessable_entity
      return
    end

    CsatSurveyService.new(conversation: @conversation).perform(manual: true)
    head :ok
  rescue StandardError => e
    Rails.logger.error "CsatSurveysController#create failed for conversation #{@conversation&.id}: #{e.message}"
    render json: { error: 'Failed to send CSAT survey' }, status: :internal_server_error
  end
end
