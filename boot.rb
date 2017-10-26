require 'capybara/poltergeist'
require 'active_support'
require 'active_support/core_ext'
require 'slack-ruby-client'
require 'dotenv/load'

class UniVisitor

  def initialize
    Capybara.register_driver :poltergeist do |app|
      Capybara::Poltergeist::Driver.new(app, {:js_errors => false, :timeout => 1000 })
    end
    @session = Capybara::Session.new(:poltergeist)

    token = ENV['SLACK_TOKEN']
    Slack.configure do |config|
      config.token = token
    end
    @slack_client = Slack::Web::Client.new
  end

  def drive(world: nil, items: [], sleep_sec: 600)
    post_to_slack("Hello! This is urchin agent starting.\n World: `#{world}` , Items: `#{items}`")

    latest_records = Array.new(items.size)
    loop do
      items.each_with_index do |item, index|
        latest_records[index] = process_one_item(world: world, item: item, latest_record: latest_records[index])
      end
      sleep sleep_sec
    end
  end

  private

  def process_one_item(**params)
    records = visit_and_find(**params)
    if records.any?
      post_to_slack(records_to_slack_message(records))
    else
      post_to_slack("no new record: `#{params[:item]}`")
    end
    records.first || params[:latest_record]
  end

  def visit_and_find(world: nil, item: nil, latest_record: nil)
    host = ENV['HOST']
    uri = URI(host)
    uri.query = { w: world, i: item }.to_param

    element_query = "//div[@id='resultPain4']//table[@class='listTable']//tr[starts-with(@class, 'listRow')]"

    @session.visit uri.to_s

    results = []

    return results if @session.status_code != 200

    @session.all(:xpath, element_query).each do |element|
      record = element_to_record(element)
      break if compare_records(latest_record, record) >= 0
      results << record
      break if latest_record.nil?
    end

    results
  end

  def post_to_slack(message)
    channel = ENV['SLACK_CHANNEL']
    @slack_client.chat_postMessage(channel: channel, text: message)
  end

  def element_to_record(element)
    {
        name:     element.find(:xpath, 'td[1]').text,
        price:    element.find(:xpath, 'td[3]').text,
        time:     element.find(:xpath, 'td[6]').text,
        title:    element.find(:xpath, 'td[7]').text,
        position: element.find(:xpath, 'td[8]').text
    }
  end

  def compare_records(left, right)
    left.try(:[], :time).to_s <=> right.try(:[], :time).to_s
  end

  def records_to_slack_message(records)
    sale = "```"
    records.each do |record|
      sale << "\n#{record[:time]}: #{record[:name]}@#{record[:price]} | \"#{record[:title]}\"@(#{record[:position]})"
    end
    sale << "\n```"

    "<!here> New sale!\n#{sale}"
  end
end

world = ENV['WORLD']
items = ENV['ITEMS'].split(',')
sleep_sec = (ENV['SLEEP'] || 600).to_i

UniVisitor.new.drive(world: world, items: items, sleep_sec: sleep_sec)
