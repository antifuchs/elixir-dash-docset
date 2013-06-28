#!/usr/bin/env ruby

# Huge FIXME: This is terrible code, but it seems to work for Elixir 0.9.3.

require 'rubygems'
require 'bundler/setup'
require 'fileutils'
require 'pathname'

require 'sqlite3'
require 'nokogiri'

require 'pry'

VERSION=ARGV[0] or raise "I require a version number argument!"

docset_path = File.expand_path("../Elixir #{VERSION}.docset/Contents/Resources/Documents", __FILE__)
FileUtils.mkdir_p(docset_path)

src_path=File.expand_path("../elixir-lang.github.com", __FILE__)

Dir.chdir(src_path) do |path|
  system *%w{jekyll build}
  raise "Jekyll build failed with exit status #{$?}" unless $? == 0
end

site_path = File.join(src_path, '_site')

[
  File.join(site_path, 'docs'),
  File.join(site_path, 'images'),
  File.join(site_path, 'css'),
  File.join(site_path, 'getting_started'),
  File.join(site_path, 'crash-course.html'),
  File.join(site_path, 'index.html'),
].each do |dir|
  FileUtils.mv(dir, docset_path)
end

FileUtils.cp(File.join(docset_path, 'images', 'logo', 'drop.png'), File.join(docset_path, '..', '..', '..', 'icon.png'))

File.open(File.join(docset_path, '..', '..', 'Info.plist'), 'w') do |f|
  f.write <<-EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>Elixir-#{VERSION}</string>
  <key>CFBundleName</key>
  <string>Elixir #{VERSION}</string>
  <key>DocSetPlatformFamily</key>
  <string>Elixir</string>
  <key>isDashDocset</key>
  <true/>
  <key>dashIndexFilePath</key>
  <string>crash-course.html</string>
</dict>
</plist>
EOF
end

def frob_documentation(document, title, relative_count)
  document.css('#header').remove
  document.css('.widget').remove
  document.css('.pagination').remove
  document.css('link[rel="stylesheet"]').each {|el| el['href']='../'*(relative_count) + './' + el['href'] if el['href'].start_with?('/')}
  document.css('title').each {|el| el.content = title }

  # Rewrite links to be more relative:
  document.xpath('//a[@href]').each do |link|
    link['href'] = case link['href']
    when %r{^/}
      ('../' * relative_count) + './' + link['href']
    else
      link['href']
    end
  end

  document.to_s
end

css = File.read(File.join(docset_path, 'css', 'style.css'))
File.open(File.join(docset_path, 'css', 'style.css'), 'w') do |f|
  css.gsub!(/^\s*width: 68\..*$/, '')
  css.gsub!(/^\s*max-width: 940px.*$/, '')
  f.write(css)
end

def make_function_links(doc, db)
  doc.xpath('//ul[@id="full_list"]/ul//li').each do |entry|
    parent_module = entry.xpath('./small').first
    link = entry.xpath('./span/a').first
    next unless link['href'].include?('#')
    title = parent_module.text + '.' + link.text
    db.execute(%Q{INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('#{title}', 'Function', '/docs/stable/#{link['href']}');})
  end
end

begin
  db = SQLite3::Database.open File.join(docset_path, '..', 'docSet.dsidx')
  db.execute('CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);')
  db.execute('CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);')

  # Documentation sections:
  (Dir[File.join(docset_path, 'getting_started', '**', '*.html')] + [File.join(docset_path, 'crash-course.html')]).each do |file|
    relative_filename = Pathname.new(file).relative_path_from(Pathname.new(File.join(docset_path))).to_s

    doc = Nokogiri.parse(File.read(file))
    title = doc.css('title').text
    if File.basename(file) == 'crash-course.html'
      title = "Erlang/Elixir Syntax: A Crash Course"
    elsif (dirname = File.basename(File.dirname(file))) != 'getting_started'
      title = dirname.capitalize + " - " + title
    end

    title.gsub!(/ . Elixir$/, '')
    File.open(file, 'w') { |f| f.write(frob_documentation(doc, title, relative_filename.count('/'))) }
    db.execute(%Q{INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('#{title}', 'Section', '#{relative_filename}');})
  end

  # Indexing allll the modules/records/protocols/functions:
  doc = Nokogiri.parse(File.read(File.join(docset_path, 'docs', 'stable', 'modules_list.html')))
  doc.xpath('//ul[@id="full_list"]/li/span/a').map{|el| [el.inner_text, el['href'], el]}.each do |title, link, el|
    db.execute(%Q{INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('#{title}', 'Module', '/docs/stable/#{link}');})
  end
  make_function_links(doc, db)

  doc = Nokogiri.parse(File.read(File.join(docset_path, 'docs', 'stable', 'records_list.html')))
  doc.xpath('//ul[@id="full_list"]/li/span/a').map{|el| [el.inner_text, el['href'], el]}.each do |title, link, el|
    db.execute(%Q{INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('#{title}', 'Record', '/docs/stable/#{link}');})
  end
  ## These errors don't usually have useful docs, so let's skip them for now:
  # make_function_links(doc, db)

  doc = Nokogiri.parse(File.read(File.join(docset_path, 'docs', 'stable', 'protocols_list.html')))
  doc.xpath('//ul[@id="full_list"]/li/span/a').map{|el| [el.inner_text, el['href'], el]}.each do |title, link, el|
    db.execute(%Q{INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('#{title}', 'Protocol', '/docs/stable/#{link}');})
  end
  make_function_links(doc, db)
ensure
  db.close if db
end
