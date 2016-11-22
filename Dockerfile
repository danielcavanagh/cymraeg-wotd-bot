from alpine:3.4
copy Gemfile /
run apk --update add --virtual build_deps build-base \
    ruby ruby-json ruby-dev ruby-bundler libc-dev linux-headers \
    openssl-dev libxml2-dev libxslt-dev ca-certificates && \
    bundle install
copy *.rb /
entrypoint ["ruby", "main.rb"]
