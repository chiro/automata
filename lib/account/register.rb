# -*- coding: utf-8 -*-

require 'bundler/setup'
require 'haml'
require 'securerandom'

require_relative '../app/logger_ext'
require_relative '../helper'
require_relative '../user'
require_relative '../mailer'
require_relative '../reset'
require_relative '../string/random'

module Account
  class AlreadyRegistered < Exception; end
  class InvalidArguments < Exception; end

  class Register
    def page(msg = '')
      <<-EOH
!!! 5
%html
  %head
    %title= Account
    %meta{charset: "UTF-8"}
    %link{rel:  "stylesheet",
          type: "text/css",
          href: "../css/default.css"}
  %body
    = yield
    %div{id: "msg"} #{msg}
    %div{id: "footer"}
      %a{href: "../"} 提出システム トップページ
      %a{href: "./"} 戻る
      EOH
    end

    def form_email
      <<-EOH
%div
  以下のフォームにメールアドレスを入力してください．
%form{method: "POST", action: "register.cgi"}
  %fieldset
    %legend メールアドレス
    %input{type: "email", name: "email", placeholder: "hoge@example.com",
           required: true}
    %br
    %button{type: "submit"} 送信
      EOH
    end

    def form_token
      <<-EOH
%div
  メールに記載のトークンを以下に入力してください．
%form{method: "POST", action: "register.cgi"}
  %fieldset
    %legend トークン
    %input{type: "text", name: "token", required: true}
    %br
    %button{type: "submit"} 送信
      EOH
    end

    def form_signup(email, name = '', ruby = '', login = '')
      <<-EOH
%div
  ユーザ情報を入力してください．
%form{method: "POST", action: "register.cgi"}
  %fieldset
    %legend 新規登録
    %input{type: "text", name: "name", placeholder: "名前", required: true,
           value: "#{name}"}
    %br
    %input{type: "text", name: "ruby", placeholder: "ふりがな", required: true,
           value: "#{ruby}"}
    %br
    %label
      %input{type: "text", name: "login", placeholder: "学籍番号",
             pattern: "^[0-9]{10}$", required: true, value: "#{login}"}
      ※数字は半角、ハイフンなしの10桁
    %br
    %span email: #{email}
    %br
    %button{type: "submit"} 送信
      EOH
    end

    def confirm(email, name, ruby, login)
      <<-EOH
%div
  以下の情報で問題なければ登録ボタンを押してください．
%form{method: "POST", action: "register.cgi"}
  %fieldset
    %legend
    %div 名前: #{name}
    %div ふりがな: #{ruby}
    %div 学籍番号: #{login}
    %div email: #{email}
    %button{type: "submit", name: "confirm", value: "register"} 登録
    %button{type: "submit", name: "confirm", value: "reset"} やり直す
      EOH
    end

    def register_succeed
      <<-EOH
%div パスワードをメールで送信しました．
      EOH
    end

    def receive_email(env, email)
      if User.all_users.any? { |u| u.email == email }
        msg = '入力されたメールアドレスは既に登録されています．'
        return Haml::Engine.new(page(msg)).render do
          Haml::Engine.new(form_email).render
        end
      end

      token = SecureRandom.urlsafe_base64(32)
      env['rack.session']['token'] = token
      env['rack.session']['email'] = email

      body = "ページに戻って，次のトークンを入力してください．\n\n#{token}"
      Mailer.send_mail(email, 'noreply', body)

      Haml::Engine.new(page).render do
        Haml::Engine.new(form_token).render
      end
    end

    def receive_token(env, email_s, token_u, token_s)
      if token_u == token_s
        return Haml::Engine.new(page).render do
          Haml::Engine.new(form_signup(email_s)).render
        end
      end
      Haml::Engine.new(page('トークンが違います．')).render do
        Haml::Engine.new(form_token).render
      end
    end

    def receive_user_info(env, email_s, name, ruby, login)
      begin
        validate(email_s, name, ruby, login)
        env['rack.session']['name']  = name
        env['rack.session']['ruby']  = ruby
        env['rack.session']['login'] = login
        return Haml::Engine.new(page).render do
          Haml::Engine.new(confirm(email_s, name, ruby, login)).render
        end
      rescue InvalidArguments
        msg = '入力された値のどれかが空か，学籍番号が10桁の半角数字ではありません．'
      rescue AlreadyRegistered
        msg = '入力された学籍番号は既に登録されています．'
      rescue => e
        logger = App::Logger.new
        logger.error(e.to_s)
        e.backtrace.each { |m| logger.error(m) }
        msg = 'エラーが発生しました．管理者に連絡してください．'
      end
      Haml::Engine.new(page(msg)).render do
        Haml::Engine.new(form_signup(email_s)).render
      end
    end

    def receive_reset(email_s, name, ruby, login)
      Haml::Engine.new(page).render do
        Haml::Engine.new(form_signup(email_s, name, ruby, login)).render
      end
    end

    def receive_confirmation(env, email, name, ruby, login)
      begin
        validate(email, name, ruby, login)
        register(email, name, ruby, login)
        env['rack.session'].clear
      rescue InvalidArguments, AlreadyRegistered => e
        logger = App::Logger.new
        logger.warn <<-EOS
Something go wrong in register.rb: These values,
email: \"#{email}\", name: \"#{name}\", ruby: \"#{ruby}\", login: \"#{login}\"
should have been validated, but validation fails with error: #{e}
        EOS
        return Haml::Engine.new(page).render do
          Haml::Engine.new(form_signup(email, name, ruby, login)).render
        end
      end

      Haml::Engine.new(page).render do
        Haml::Engine.new(register_succeed).render
      end
    end

    def call(env)
      helper = Helper.new(env)

      email     = helper.params['email']
      name      = helper.params['name']
      ruby      = helper.params['ruby']
      login     = helper.params['login']
      token_u   = helper.params['token']
      email_s   = env['rack.session']['email']
      name_s    = env['rack.session']['name']
      ruby_s    = env['rack.session']['ruby']
      login_s   = env['rack.session']['login']
      token_s   = env['rack.session']['token']
      confirmed = helper.params['confirm'] == 'register'
      reset     = helper.params['confirm'] == 'reset'

      if token_u && token_s
        return helper.ok(receive_token(env, email_s, token_u, token_s))
      end

      return helper.ok(receive_email(env, email)) if email
      return helper.ok(receive_reset(email_s, name_s, ruby_s, login_s)) if reset

      if email_s && name && ruby && login
        return helper.ok(receive_user_info(env, email_s, name, ruby, login))
      end

      if confirmed && email_s && name_s && ruby_s && login_s
        html = receive_confirmation(env, email_s, name_s, ruby_s, login_s)
        return helper.ok(html)
      end

      html = Haml::Engine.new(page).render do
        Haml::Engine.new(form_email).render
      end
      helper.ok(html)
    end

    def validate(email, name, _ruby, login)
      login = login.to_s
      fail InvalidArguments if login !~ /^[0-9]{10}$/
      fail InvalidArguments if name.empty?
      fail InvalidArguments if email !~ /^[^@]+@.+$/
      # Checks whether the email address or the login are already used or not.
      fail AlreadyRegistered if User.all_users.any? do |u|
        u.email == email || u.real_login == login
      end
    end

    def register(email, name, ruby, login)
      User.add(
        'name'  => name,
        'ruby'  => ruby,
        'login' => login.to_s,
        'email' => email
      )
      App.reset(email, :passwd_issue)
    end
  end
end
