PhishLulz
---------

PhishLulz is a Ruby toolset aimed at automating Phishing activities.

When you start a phishing campaign, a dedicated Amazon EC2 (Debian 7) instance is spawned.
The VM comes with various open source tools that have been glued together. The two main components are:

* PhishingFrenzy (https://github.com/pentestgeek/phishing-frenzy)
* BeEF (https://github.com/beefproject/beef)
 
PhishLulz comes with its own self-signed CA: this is needed to generate self-signed certs for the PhishingFrenzy admin UI. 
You will also find a bunch of cool phishing templates (which are not in PF) that you can quickly re-use in your scenarios.

Automatic domain registration is still TODO, however you can play with the almost-working code for the NameCheap registrar.

PhishLulz AWS AMI
-----------------
The public AMI id is: ami-141bb974
You want to clone that, add your SSH keys, and use your nre clone.

The following are default passwords for various services, change them.

* MySQL root user: phishlulz_mysql
* PhishingFrenzy admin user: phishlulz_frenzy
* BeEF beef user: phishlulz_beef

To change the default admin user password/email for PhishingFrenzy use the Rails console:
cd /var/www/phishing-frenzy && RAILS_ENV=production rails console
admin = Admin.first
admin.password = "newpasswd"
admin.email = "newemail"
admin.save!
exit


PhishLulz Toolset
-----------------
* **phish_lulz**: main script to start/stop phishing instances
* **tools/find_resources**: multi-threaded subdomain discovery and fingerprinting tool
* **tools/mailboxbug**: multi-threaded webmail data extruder 
* **tools/mail_parser**: simple script to extract html/txt from an .eml email file
* **namecheap_wrapper**: WIP for automated domain registration


PhishLulz material released at KiwiCon X 
----------------------------------------
[![KiwiCon X talk slides](http://www.slideshare.net/micheleorru2/practical-phishing-automation-with-phishlulz-kiwicon-x)](http://www.slideshare.net/micheleorru2/practical-phishing-automation-with-phishlulz-kiwicon-x)

[![PhishLulz phishing](https://vimeo.com/192742480)](https://vimeo.com/192742480)

[![MailBoxBug against Outlook Office365](https://vimeo.com/192742686)](https://vimeo.com/192742686)


Requirements
------------
* Amazon AWS account (see main config.yaml)
* Non-Winzozz OS (path separators are hardcoded on purpose to don't make it compatible with Winzozz)
* ssh, scp, openssl in PATH
* Sane Ruby environment (RVM suggested). Install the required gems with: 
gem install sinatra thin watir-webdriver headless colorize datamapper dm-sqlite-adapter dm-timestamps dm-migrations fog nokogiri mail net-ssh --no-rdoc --no-ri
* Gecko/Chrome drivers 

To instrument Firefox you need to have the geckodriver binary in your PATH.
Download it from https://github.com/mozilla/geckodriver/releases
Same thing applies if you prefer instrumenting Chrome, you need the chromedriver.

Once you have the binary, make sure it's in the PATH:
export PATH=$PATH:path_to_driver_dir

Finally, make sure the MailBoxBug data extrusion domain has a valid HTTPS certificate (Mixed content...)

Get Involved 
------------

PhishLulz is supposed to be used by experienced people, so make sure you know what you're doing
before spamming the Github issue tracker with non-sense questions.

If you like PhishLulz and the toolset, pull requests would be much appreciated ;-) 

__Twitter:__ @antisnatchor
