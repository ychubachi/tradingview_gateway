class ApplicationController < ActionController::API
  rescue_from Exception, with: :render_500

  def render_500(e)
    ExceptionNotifier.notify_exception(e, :env => request.env, :data => {:message => "error"})
    render template: 'errors/error_500', status: 500
  end
end
