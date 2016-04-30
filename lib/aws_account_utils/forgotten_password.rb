require 'aws_account_utils/base'
require 'tempfile'
require 'open-uri'
require 'rmagick'
require 'tesseract'

module AwsAccountUtils
  class ForgottenPassword < Base
    attr_reader :logger, :browser

    def initialize(logger, browser)
      @logger = logger
      @browser = browser
    end

    def request_password_reset_link(account_email)
      logger.debug 'Requesting password reset link.'
      browser.goto url
      screenshot(browser, "1")

      src = browser.div(:id => 'ap_captcha_img').image.src
      logger.debug 'Processing captcha image: ' + src

      captcha_orig = Tempfile.new(['captcha-', '.jpg'])
      captcha_orig.write open(src).read
      captcha_orig.close
      logger.debug 'Captcha written to: ' + captcha_orig.path

      captcha_adj = Tempfile.new(['captcha-adj-', '.jpg'])
      img = Magick::Image.read(captcha_orig.path)
      img.first.level(0.0, 0.5 * Magick::QuantumRange, 1.0).write(captcha_adj.path)
      logger.debug 'Adjusted captcha written to: ' + captcha_adj.path

      e = Tesseract::Engine.new {|e|
        e.language  = :eng
        e.whitelist = '0123456789abcdefghijklmnopqrstuvwxyz'
        e.page_segmentation_mode = 8
      }

      ocr_text = e.text_for(captcha_adj.path).strip
      captcha_adj.close
      logger.debug 'Captcha guess: ' + ocr_text

      browser.text_field(:id =>"ap_email").when_present.set account_email
      browser.text_field(:id =>"ap_captcha_guess").when_present.set ocr_text
      screenshot(browser, "2")

      rnd = Random.new
      sleep(rnd.rand(0.5..1.0))
      browser.button(:id => "continue-input").when_present.click
      raise StandardError if browser.div(:id => /message_(error|warning)/).exist?
      browser.h2(:text => /Check your e-mail\./).exist?

    rescue Watir::Wait::TimeoutError, Net::ReadTimeout => e
      screenshot(browser, "error")
      raise StandardError, "#{self.class.name} - #{e}"
    rescue StandardError => e
      screenshot(browser, "error")
      error_header = browser.div(:id => /message_(error|warning)/).h6.text
      error_body = browser.div(:id => /message_(error|warning)/).p.text
      raise StandardError, "AWS Request Password Reset Error: \"#{error_header}: #{error_body}\""
    ensure
      unless captcha_orig.nil?
        captcha_orig.unlink
      end
      unless captcha_adj.nil?
        captcha_adj.unlink
      end
    end

    def reset_password(reset_url, account_password)
      logger.debug 'Requesting password reset page.'
      browser.goto reset_url
      screenshot(browser, "1")

      browser.text_field(:id =>"ap_fpp_password").when_present.set account_password
      browser.text_field(:id =>"ap_fpp_password_check").when_present.set account_password 
      screenshot(browser, "2")

      logger.debug 'Submitting new password.'
      browser.button(:id => "continue-input").when_present.click
      raise StandardError if browser.div(:id => /message_(error|warning)/).exist?
      screenshot(browser, "3")
      browser.div(:text => /You have successfully changed your password\./).exist?

    rescue Watir::Wait::TimeoutError, Net::ReadTimeout => e
      screenshot(browser, "error")
      raise StandardError, "#{self.class.name} - #{e}"
    rescue StandardError => e
      screenshot(browser, "error")
      error_header = browser.div(:id => /message_(error|warning)/).h6.text
      error_body = browser.div(:id => /message_(error|warning)/).p.text
      raise StandardError, "AWS Request Password Reset Error: \"#{error_header}: #{error_body}\""
    end

    private
    def url
      url ="https://www.amazon.com/ap/forgotpassword?"
      url<< "openid.return_to=https%3A%2F%2Fsignin.aws.amazon.com%2Foauth%3Fresponse_type%3Dcode%26client_id%3Darn%253Aaws%253Aiam%253A%253A015428540659%253Auser%252Fhomepage%26redirect_uri%3Dhttps%253A%252F%252Fconsole.aws.amazon.com%252Fconsole%252Fhome%253Fnc2%253Dh_m_mc%2526state%253DhashArgs%252523%2526isauthcode%253Dtrue%26noAuthCookie%3Dtrue"
      url<< "&openid.assoc_handle=aws"
      url<< "&openid.mode=checkid_setup"
      url<< "&pageId=aws"
      url<< "&openid.ns=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0"
    end
  end
end

