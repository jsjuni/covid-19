# frozen_string_literal: true

require 'logger-application'
require 'uri'
require 'net/http'
require 'json'
require 'digest'

# Fetch
class Fetch < Logger::Application

  URI = 'https://api.github.com/repos'
  OWNER = 'nytimes'
  REPO = 'covid-19-data'
  FILE_PATS = [
    /us-states\.csv/,
    /us-counties-\d{4}\.csv/
  ].freeze

  def initialize(argv)
    super('fetch')
    @token = argv[0]
    @level = Logger::DEBUG
  end

  def run
    log(INFO, 'begin')
    repo_shas = get_repo_shas(URI, @token, OWNER, REPO)
    local_shas = get_local_shas(repo_shas.keys)
    to_fetch = get_to_fetch(repo_shas, local_shas)
    to_fetch.each do |file|
      log(INFO, "fetch #{file}")
      fetch(URI, @token, OWNER, REPO, file)
    end
    log(INFO, 'end')
    0
  end

  def get_repo_shas(uri, token, owner, repo)
    uri = URI("#{uri}/#{owner}/#{repo}/contents")
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      req = Net::HTTP::Get.new(uri.request_uri)
      req['Authorization'] = "token #{token}"
      req['Accept'] = 'application/vnd.github.v4.raw'
      res = http.request(req)
      JSON.parse(res.body).select do |e|
        FILE_PATS.any? { |pat| e['name'] =~ pat }
      end.each_with_object({}) do |o, h|
        h[o['name']] = o['sha']
      end
    end
  end

  def get_local_shas(files)
    files.select do |file|
      File.file?(file)
    end.each_with_object({}) do |file, h|
      contents = File.open(file, 'rb').read
      h[file] = Digest::SHA1.hexdigest("blob #{contents.length}\0#{contents}")
    end
  end

  def get_to_fetch(repo_shas, local_shas)
    repo_shas.select do |file, repo_sha|
      !local_shas.has_key?(file) || local_shas[file] != repo_shas[file]
    end.keys
  end

  def fetch(uri, token, owner, repo, file)
    uri = URI("#{uri}/#{owner}/#{repo}/contents/#{file}")
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      req = Net::HTTP::Get.new(uri.request_uri)
      req['Authorization'] = "token #{token}"
      req['Accept'] = 'application/vnd.github.v4.raw'
      res = http.request(req)
      File.open(file, 'w').write(res.body)
    end
  end
end

fetch = Fetch.new(ARGV).run
