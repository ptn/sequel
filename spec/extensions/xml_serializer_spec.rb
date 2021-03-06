require File.join(File.dirname(File.expand_path(__FILE__)), "spec_helper")

begin
  require 'nokogiri'
rescue LoadError => e
  skip_warn "xml_serializer plugin: can't load nokogiri (#{e.class}: #{e})"
else
describe "Sequel::Plugins::XmlSerializer" do
  before do
    class ::Artist < Sequel::Model
      unrestrict_primary_key
      plugin :xml_serializer
      columns :id, :name
      @db_schema = {:id=>{:type=>:integer}, :name=>{:type=>:string}}
      one_to_many :albums
    end
    class ::Album < Sequel::Model
      unrestrict_primary_key
      attr_accessor :blah
      plugin :xml_serializer
      columns :id, :name, :artist_id
      @db_schema = {:id=>{:type=>:integer}, :name=>{:type=>:string}, :artist_id=>{:type=>:integer}}
      many_to_one :artist
    end
    @artist = Artist.load(:id=>2, :name=>'YJM')
    @artist.associations[:albums] = []
    @album = Album.load(:id=>1, :name=>'RF')
    @album.artist = @artist
    @album.blah = 'Blah'
  end
  after do
    Object.send(:remove_const, :Artist)
    Object.send(:remove_const, :Album)
  end

  it "should round trip successfully" do
    Artist.from_xml(@artist.to_xml).should == @artist
    Album.from_xml(@album.to_xml).should == @album
  end

  it "should round trip successfully for namespaced models" do
    module XmlSerializerTest
      class Artist < Sequel::Model
        unrestrict_primary_key
        plugin :xml_serializer
        columns :id, :name
        @db_schema = {:id=>{:type=>:integer}, :name=>{:type=>:string}}
      end 
    end
    artist = XmlSerializerTest::Artist.load(:id=>2, :name=>'YJM')
    XmlSerializerTest::Artist.from_xml(artist.to_xml).should == artist
  end

  it "should round trip successfully with empty strings" do
    artist = Artist.load(:id=>2, :name=>'')
    Artist.from_xml(artist.to_xml).should == artist
  end

  it "should round trip successfully with nil values" do
    artist = Artist.load(:id=>2, :name=>nil)
    Artist.from_xml(artist.to_xml).should == artist
  end

  it "should handle the :only option" do
    Artist.from_xml(@artist.to_xml(:only=>:name)).should == Artist.load(:name=>@artist.name)
    Album.from_xml(@album.to_xml(:only=>[:id, :name])).should == Album.load(:id=>@album.id, :name=>@album.name)
  end

  it "should handle the :except option" do
    Artist.from_xml(@artist.to_xml(:except=>:id)).should == Artist.load(:name=>@artist.name)
    Album.from_xml(@album.to_xml(:except=>[:id, :artist_id])).should == Album.load(:name=>@album.name)
  end

  it "should handle the :include option for associations" do
    Artist.from_xml(@artist.to_xml(:include=>:albums), :associations=>:albums).albums.should == [@album]
    Album.from_xml(@album.to_xml(:include=>:artist), :associations=>:artist).artist.should == @artist
  end

  it "should handle the :include option for arbitrary attributes" do
    Album.from_xml(@album.to_xml(:include=>:blah)).blah.should == @album.blah
  end

  it "should handle multiple inclusions using an array for the :include option" do
    a = Album.from_xml(@album.to_xml(:include=>[:blah, :artist]), :associations=>:artist)
    a.blah.should == @album.blah
    a.artist.should == @artist
  end

  it "should handle cascading using a hash for the :include option" do
    Artist.from_xml(@artist.to_xml(:include=>{:albums=>{:include=>:artist}}), :associations=>{:albums=>{:associations=>:artist}}).albums.map{|a| a.artist}.should == [@artist]
    Album.from_xml(@album.to_xml(:include=>{:artist=>{:include=>:albums}}), :associations=>{:artist=>{:associations=>:albums}}).artist.albums.should == [@album]

    Artist.from_xml(@artist.to_xml(:include=>{:albums=>{:only=>:name}}), :associations=>{:albums=>{:fields=>%w'name'}}).albums.should == [Album.load(:name=>@album.name)]
    Album.from_xml(@album.to_xml(:include=>{:artist=>{:except=>:name}}), :associations=>:artist).artist.should == Artist.load(:id=>@artist.id)

    Artist.from_xml(@artist.to_xml(:include=>{:albums=>{:include=>{:artist=>{:include=>:albums}}}}), :associations=>{:albums=>{:associations=>{:artist=>{:associations=>:albums}}}}).albums.map{|a| a.artist.albums}.should == [[@album]]
    Album.from_xml(@album.to_xml(:include=>{:artist=>{:include=>{:albums=>{:only=>:name}}}}), :associations=>{:artist=>{:associations=>{:albums=>{:fields=>%w'name'}}}}).artist.albums.should == [Album.load(:name=>@album.name)]
  end

  qspecify "should automatically cascade parsing for all associations if :all_associations is used" do
    Artist.from_xml(@artist.to_xml(:include=>{:albums=>{:include=>:artist}}), :all_associations=>true).albums.map{|a| a.artist}.should == [@artist]
   end
  
  it "should handle the :include option cascading with an empty hash" do
    Album.from_xml(@album.to_xml(:include=>{:artist=>{}}), :associations=>:artist).artist.should == @artist
    Album.from_xml(@album.to_xml(:include=>{:blah=>{}})).blah.should == @album.blah
  end

  it "should support #from_xml to set column values" do
    @artist.from_xml('<album><name>AS</name></album>')
    @artist.name.should == 'AS'
    @artist.id.should == 2
  end

  it "should support a :name_proc option when serializing and deserializing" do
    Album.from_xml(@album.to_xml(:name_proc=>proc{|s| s.reverse}), :name_proc=>proc{|s| s.reverse}).should == @album
  end

  it "should support a :camelize option when serializing and :underscore option when deserializing" do
    Album.from_xml(@album.to_xml(:camelize=>true), :underscore=>true).should == @album
  end

  it "should support a :camelize option when serializing and :underscore option when deserializing" do
    Album.from_xml(@album.to_xml(:dasherize=>true), :underscore=>true).should == @album
  end

  it "should support an :encoding option when serializing" do
    ["<?xml version=\"1.0\" encoding=\"UTF-8\"?><artist><id>2</id><name>YJM</name></artist>",
     "<?xml version=\"1.0\" encoding=\"UTF-8\"?><artist><name>YJM</name><id>2</id></artist>"].should include(@artist.to_xml(:encoding=>'UTF-8').gsub(/\n */m, ''))
  end

  it "should support a :builder_opts option when serializing" do
    ["<?xml version=\"1.0\" encoding=\"UTF-8\"?><artist><id>2</id><name>YJM</name></artist>",
     "<?xml version=\"1.0\" encoding=\"UTF-8\"?><artist><name>YJM</name><id>2</id></artist>"].should include(@artist.to_xml(:builder_opts=>{:encoding=>'UTF-8'}).gsub(/\n */m, ''))
  end

  it "should support an :types option when serializing" do
    ["<?xml version=\"1.0\"?><artist><id type=\"integer\">2</id><name type=\"string\">YJM</name></artist>",
     "<?xml version=\"1.0\"?><artist><name type=\"string\">YJM</name><id type=\"integer\">2</id></artist>"].should include(@artist.to_xml(:types=>true).gsub(/\n */m, ''))
  end

  it "should support an :root_name option when serializing" do
    ["<?xml version=\"1.0\"?><ar><id>2</id><name>YJM</name></ar>",
     "<?xml version=\"1.0\"?><ar><name>YJM</name><id>2</id></ar>"].should include(@artist.to_xml(:root_name=>'ar').gsub(/\n */m, ''))
  end

  it "should support an :array_root_name option when serializing arrays" do
    artist = @artist
    Artist.dataset.meta_def(:all){[artist]}
    ["<?xml version=\"1.0\"?><ars><ar><id>2</id><name>YJM</name></ar></ars>",
     "<?xml version=\"1.0\"?><ars><ar><name>YJM</name><id>2</id></ar></ars>"].should include(Artist.to_xml(:array_root_name=>'ars', :root_name=>'ar').gsub(/\n */m, ''))
  end

  it "should raise an exception for xml tags that aren't associations, columns, or setter methods" do
    Album.send(:undef_method, :blah=)
    proc{Album.from_xml(@album.to_xml(:include=>:blah))}.should raise_error(Sequel::Error)
  end

  it "should support a to_xml class and dataset method" do
    album = @album
    Album.dataset.meta_def(:all){[album]}
    Album.array_from_xml(Album.to_xml).should == [@album]
    Album.array_from_xml(Album.to_xml(:include=>:artist), :associations=>:artist).map{|x| x.artist}.should == [@artist]
    Album.array_from_xml(Album.dataset.to_xml(:only=>:name)).should == [Album.load(:name=>@album.name)]
  end

  it "should have to_xml dataset method respect an :array option" do
    a = Album.load(:id=>1, :name=>'RF', :artist_id=>3)
    Album.array_from_xml(Album.to_xml(:array=>[a])).should == [a]

    a.associations[:artist] = artist = Artist.load(:id=>3, :name=>'YJM')
    Album.array_from_xml(Album.to_xml(:array=>[a], :include=>:artist), :associations=>:artist).first.artist.should == artist

    artist.associations[:albums] = [a]
    x = Artist.array_from_xml(Artist.to_xml(:array=>[artist], :include=>:albums), :associations=>:albums)
    x.should == [artist]
    x.first.albums.should == [a]
  end

  it "should raise an error if the dataset does not have a row_proc" do
    proc{Album.dataset.naked.to_xml}.should raise_error(Sequel::Error)
  end

  qspecify "should have :associations option take precedence over :all_assocations" do
    Artist.from_xml(@artist.to_xml(:include=>:albums), :associations=>[], :all_associations=>true, :fields=>[]).associations.should == {}
  end

  qspecify "should allow overriding of :all_columns options in associated objects" do
    Album.restrict_primary_key
    Artist.from_xml(@artist.to_xml(:include=>:albums), :associations=>{:albums=>{:fields=>[:id, :name, :artist_id], :missing=>:raise}}, :all_columns=>true).albums
  end

  qspecify "should allow setting columns that are restricted if :all_columns is used" do
    Artist.restrict_primary_key
    Artist.from_xml(@artist.to_xml, :all_columns=>true).should == @artist
  end

  it "should raise an error if using parsing empty xml" do
    proc{Artist.from_xml("<?xml version=\"1.0\"?>\n")}.should raise_error(Sequel::Error)
    proc{Artist.array_from_xml("<?xml version=\"1.0\"?>\n")}.should raise_error(Sequel::Error)
  end

  qspecify "should raise an error if using :all_columns and non-column is in the XML" do
    proc{Artist.from_xml("<?xml version=\"1.0\"?>\n<artist>\n  <foo>bar</foo>\n  <id>2</id>\n</artist>\n", :all_columns=>true)}.should raise_error(Sequel::Error)
  end

  it "should raise an error if attempting to set a restricted column and :all_columns is not used" do
    Artist.restrict_primary_key
    proc{Artist.from_xml(@artist.to_xml)}.should raise_error(Sequel::Error)
  end

  it "should raise an error if an unsupported association is passed in the :associations option" do
    Artist.association_reflections.delete(:albums)
    proc{Artist.from_xml(@artist.to_xml(:include=>:albums), :associations=>:albums)}.should raise_error(Sequel::Error)
  end

  it "should raise an error if using from_xml and XML represents an array" do
    proc{Artist.from_xml(Artist.to_xml(:array=>[@artist]))}.should raise_error(Sequel::Error)
  end

  it "should raise an error if using array_from_xml and XML does not represent an array" do
    proc{Artist.array_from_xml(@artist.to_xml)}.should raise_error(Sequel::Error)
  end

  it "should raise an error if using an unsupported :associations option" do
    proc{Artist.from_xml(@artist.to_xml, :associations=>'')}.should raise_error(Sequel::Error)
  end
end
end
