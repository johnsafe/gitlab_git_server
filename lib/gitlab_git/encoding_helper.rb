module EncodingHelper
  extend self

  def encode_rpc!(message)
    return nil unless message.respond_to? :force_encoding
    # return message if message type is binary
    detect = EncodingHelper.detect_instance.detect(message[0, 1000])
    return message.force_encoding("BINARY") if detect && detect[:type] == :binary

    if detect && detect[:confidence] == 100
      # encoding message to detect encoding
      message.force_encoding(detect[:encoding])
    else
      detect = CharDet.detect(message)
      message.force_encoding(detect[:encoding]) if detect.confidence > 0.6
    end

    # encode and clean the bad chars
    message.replace clean(message)
  rescue
    encoding = detect ? detect[:encoding] : "unknown"
    "--broken encoding: #{encoding}"
  end

  def data_binary?(data)
    detect = EncodingHelper.detect_instance.detect(data[0, 1000])
    if detect
      detect[:type] == :binary && detect[:confidence] == 100
    else
      detect = CharDet.detect(data[0, 1000])
      detect[:encoding] == 'ascii' && detect[:confidence] == 1.0
    end
  end

  def detect_instance
    @detector ||= CharlockHolmes::EncodingDetector.new
  end

  module_function :detect_instance

end
