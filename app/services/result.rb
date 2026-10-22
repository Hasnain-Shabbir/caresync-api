# Outcome of a service call: success with a value, or failure with a stable code and a safe message.
# On a validation failure, value is the invalid record so the caller can read its errors.
Result = Data.define(:success, :value, :code, :message) do
  def self.success(value = nil)
    new(success: true, value: value, code: nil, message: nil)
  end

  def self.failure(code, message, value = nil)
    new(success: false, value: value, code: code, message: message)
  end

  def success? = success
  def failure? = !success
end
