if user_signed_in? and ( current_user.admin? or current_user.id == @submission.user_id )
  json.extract! @submission, :id, :code, :compiler, :result, :score, :created_at, :updated_at
end
