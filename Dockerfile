from alpine:3.4
copy Gemfile main.rb /
run apk --update add --virtual build_deps build-base \
    ruby ruby-dev ruby-bundler libc-dev linux-headers \
    openssl-dev libxml2-dev libxslt-dev ca-certificates && \
    bundle install
entrypoint ["ruby", "main.rb"]
