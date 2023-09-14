require "test_helper"
require "shrine/storage/file_system"
require "set"

describe Shrine::UploadedFile do
  before do
    @uploader = uploader(:store)
    @shrine   = @uploader.class
  end

  def uploaded_file(data = {})
    data = { id: "foo", storage: :store, metadata: {} }.merge(data)
    @shrine::UploadedFile.new(data)
  end

  it "is an IO" do
    uploaded_file = @uploader.upload(fakeio)

    assert_respond_to uploaded_file, :read
    assert_respond_to uploaded_file, :rewind
    assert_respond_to uploaded_file, :eof?
    assert_respond_to uploaded_file, :close
  end

  describe "#initialize" do
    it "accepts data hash with symbol keys" do
      uploaded_file = @shrine::UploadedFile.new(
        id:       "foo",
        storage:  :store,
        metadata: { "foo" => "bar" },
      )

      assert_equal "foo",                uploaded_file.id
      assert_equal :store,               uploaded_file.storage_key
      assert_equal Hash["foo" => "bar"], uploaded_file.metadata
    end

    it "accepts data hash with string keys" do
      uploaded_file = @shrine::UploadedFile.new(
        "id"       => "foo",
        "storage"  => "store",
        "metadata" => { "foo" => "bar" },
      )

      assert_equal "foo",                uploaded_file.id
      assert_equal :store,               uploaded_file.storage_key
      assert_equal Hash["foo" => "bar"], uploaded_file.metadata
    end

    it "allows being initialized with a frozen hash" do
      @shrine::UploadedFile.new({
        id:       "foo",
        storage:  :store,
        metadata: { "foo" => "bar" },
      }.freeze)
    end

    it "initializes metadata if absent" do
      uploaded_file = uploaded_file(metadata: nil)

      assert_equal Hash.new, uploaded_file.metadata
    end

    it "raises an error if storage is not registered" do
      assert_raises(Shrine::Error) { uploaded_file(storage: :foo) }
    end

    it "raises an error on invalid data" do
      assert_raises(Shrine::Error) { uploaded_file(id: nil, storage: nil) }
      assert_raises(Shrine::Error) { uploaded_file(id: nil) }
      assert_raises(Shrine::Error) { uploaded_file(storage: nil) }
    end
  end

  describe "#original_filename" do
    it "returns filename from metadata" do
      uploaded_file = uploaded_file(metadata: { "filename" => "foo.jpg" })
      assert_equal "foo.jpg", uploaded_file.original_filename

      uploaded_file = uploaded_file(metadata: { "filename" => nil })
      assert_nil uploaded_file.original_filename

      uploaded_file = uploaded_file(metadata: {})
      assert_nil uploaded_file.original_filename
    end
  end

  describe "#extension" do
    it "extracts file extension from id" do
      uploaded_file = uploaded_file(id: "foo.jpg")
      assert_equal "jpg", uploaded_file.extension

      uploaded_file = uploaded_file(id: "foo")
      assert_nil uploaded_file.extension
    end

    it "extracts file extension from filename" do
      uploaded_file = uploaded_file(metadata: { "filename" => "foo.jpg" })
      assert_equal "jpg", uploaded_file.extension

      uploaded_file = uploaded_file(metadata: { "filename" => "foo" })
      assert_nil uploaded_file.extension

      uploaded_file = uploaded_file(metadata: {})
      assert_nil uploaded_file.extension
    end

    # Some storages may reformat the file on upload, changing its extension,
    # so we want to make sure that we take the new extension, and not the
    # extension file had before upload.
    it "prefers extension from id over one from filename" do
      uploaded_file = uploaded_file(id: "foo.jpg", metadata: { "filename" => "foo.png" })
      assert_equal "jpg", uploaded_file.extension
    end

    it "downcases the extracted extension" do
      uploaded_file = uploaded_file(id: "foo.JPG")
      assert_equal "jpg", uploaded_file.extension

      uploaded_file = uploaded_file(metadata: { "filename" => "foo.JPG" })
      assert_equal "jpg", uploaded_file.extension
    end

    it "does not include query params from shrine-url ids in extension" do
      uploaded_file = uploaded_file(id: "http://example.com/path.html?key=value", storage: :cache)
      assert_equal "html", uploaded_file.extension

      uploaded_file = uploaded_file(id: "http://example.com/path.jpg?test.w23fs", storage: :cache)
      assert_equal "jpg", uploaded_file.extension

      uploaded_file = uploaded_file(id: "http://example.com/path?key=value", storage: :cache)
      assert_nil uploaded_file.extension
    end

    it "can still handle non-url extensions with question marks" do
      uploaded_file = uploaded_file(id: "foo.?xx")
      assert_equal "?xx", uploaded_file.extension

      uploaded_file = uploaded_file(id: "foo.x?x")
      assert_equal "x?x", uploaded_file.extension

      uploaded_file = uploaded_file(id: "foo.xx?")
      assert_equal "xx?", uploaded_file.extension
    end
  end

  describe "#size" do
    it "returns size from metadata" do
      uploaded_file = uploaded_file(metadata: { "size" => 50 })
      assert_equal 50, uploaded_file.size

      uploaded_file = uploaded_file(metadata: { "size" => nil })
      assert_nil uploaded_file.size

      uploaded_file = uploaded_file(metadata: {})
      assert_nil uploaded_file.size
    end

    it "converts the value to integer" do
      uploaded_file = uploaded_file(metadata: { "size" => "50" })
      assert_equal 50, uploaded_file.size

      uploaded_file = uploaded_file(metadata: { "size" => "not a number" })
      assert_raises(ArgumentError) { uploaded_file.size }
    end
  end

  describe "#mime_type" do
    it "returns mime_type from metadata" do
      uploaded_file = uploaded_file(metadata: { "mime_type" => "image/jpeg" })
      assert_equal "image/jpeg", uploaded_file.mime_type

      uploaded_file = uploaded_file(metadata: { "mime_type" => nil })
      assert_nil uploaded_file.mime_type

      uploaded_file = uploaded_file(metadata: {})
      assert_nil uploaded_file.mime_type
    end

    it "has #content_type alias" do
      uploaded_file = uploaded_file(metadata: { "mime_type" => "image/jpeg" })
      assert_equal "image/jpeg", uploaded_file.content_type
    end
  end

  describe "#[]" do
    it "retrieves specified metadata value" do
      uploaded_file = uploaded_file(metadata: { "mime_type" => "image/jpeg" })
      assert_equal "image/jpeg", uploaded_file["mime_type"]
    end

    it "returns nil for missing metadata" do
      uploaded_file = uploaded_file(metadata: {})
      assert_nil uploaded_file["mime_type"]
    end
  end

  describe "#read" do
    it "delegates to underlying IO" do
      uploaded_file = @uploader.upload(fakeio("file"))
      assert_equal "file", uploaded_file.read
      uploaded_file.rewind
      assert_equal "fi", uploaded_file.read(2)
      assert_equal "le", uploaded_file.read(2)
      assert_nil  uploaded_file.read(2)
    end
  end

  describe "#eof?" do
    it "delegates to underlying IO" do
      uploaded_file = @uploader.upload(fakeio("file"))
      refute uploaded_file.eof?
      uploaded_file.read
      assert uploaded_file.eof?
    end
  end

  describe "#rewind" do
    it "delegates to underlying IO" do
      uploaded_file = @uploader.upload(fakeio("file"))
      assert_equal "file", uploaded_file.read
      uploaded_file.rewind
      assert_equal "file", uploaded_file.read
    end
  end

  describe "#close" do
    it "closes the underlying IO object" do
      uploaded_file = @uploader.upload(fakeio)
      io = uploaded_file.to_io
      uploaded_file.read
      uploaded_file.close
      assert io.closed?
    end

    # Sometimes an uploaded file will be copied over instead of reuploaded (S3),
    # in which case it's not downloaded, so we don't want that closing actually
    # downloads the file.
    it "doesn't open the file if it wasn't opened yet" do
      uploaded_file = @uploader.upload(fakeio)
      uploaded_file.storage.expects(:open).never
      uploaded_file.close
    end

    it "leaves the UploadedFile no longer #opened?" do
      uploaded_file = @uploader.upload(fakeio)
      uploaded_file.open
      uploaded_file.close

      refute uploaded_file.opened?
    end
  end

  describe "#url" do
    it "delegates to underlying storage" do
      uploaded_file = uploaded_file(id: "foo")
      assert_equal "memory://foo", uploaded_file.url
    end

    it "forwards given options to storage" do
      uploaded_file = uploaded_file(id: "foo")
      uploaded_file.storage.expects(:url).with("foo", { foo: "foo" })
      uploaded_file.url(foo: "foo")
    end
  end

  describe "#exists?" do
    it "delegates to underlying storage" do
      uploaded_file = @uploader.upload(fakeio)
      assert uploaded_file.exists?

      uploaded_file = uploaded_file({})
      refute uploaded_file.exists?
    end
  end

  describe "#open" do
    it "returns the underlying IO if no block given" do
      uploaded_file = @uploader.upload(fakeio)
      assert_instance_of StringIO, uploaded_file.open
      refute uploaded_file.open.closed?
      refute_equal uploaded_file, uploaded_file.open
    end

    it "closes the previuos IO" do
      uploaded_file = @uploader.upload(fakeio)
      io1 = uploaded_file.open
      io2 = uploaded_file.open
      refute_equal io1, io2
      assert io1.closed?
    end

    it "yields to the block if it's given" do
      uploaded_file = @uploader.upload(fakeio)
      uploaded_file.open { @called = true }
      assert @called
    end

    it "yields the opened IO" do
      uploaded_file = @uploader.upload(fakeio("file"))
      uploaded_file.open do |io|
        assert_instance_of StringIO, io
        assert_equal "file", io.read
      end
    end

    it "makes itself open as well" do
      uploaded_file = @uploader.upload(fakeio)
      uploaded_file.open do |io|
        assert_equal uploaded_file.to_io, io
      end
    end

    it "closes the IO after block finishes" do
      uploaded_file = @uploader.upload(fakeio)
      uploaded_file.open { |io| @io = io }
      assert_raises(IOError) { @io.read }
    end

    it "resets the uploaded file ready to be opened again" do
      uploaded_file = @uploader.upload(fakeio("file"))
      uploaded_file.open { }
      assert_equal "file", uploaded_file.read
    end

    it "opens even if it was closed" do
      uploaded_file = @uploader.upload(fakeio("file"))
      uploaded_file.read
      uploaded_file.close
      uploaded_file.open { |io| assert_equal "file", io.read }
    end

    it "closes the file even if error has occured" do
      uploaded_file = @uploader.upload(fakeio)
      assert_raises(RuntimeError, "error occured") do
        uploaded_file.open do |io|
          @io = io
          fail "error ocurred"
        end
      end
      assert @io.closed?
    end

    it "propagates any error raised in Storage#open" do
      @uploader.storage.expects(:open).raises(SystemStackError.new("open error"))
      assert_raises(SystemStackError) do
        uploaded_file.open {}
      end
    end

    it "forwards any options to Storage#open" do
      uploaded_file = @uploader.upload(fakeio)
      @uploader.storage.expects(:open).with(uploaded_file.id, foo: "bar").returns(fakeio)
      uploaded_file.open(foo: "bar") {}
    end
  end

  describe "#download" do
    it "downloads file content to a Tempfile in binary encoding" do
      uploaded_file = @uploader.upload(fakeio("file"))
      downloaded = uploaded_file.download
      assert_instance_of Tempfile, downloaded
      refute downloaded.closed?
      assert_match "file", downloaded.read
      assert downloaded.binmode?
    end

    it "reuses the internal IO object if opened" do
      uploaded_file = @uploader.upload(fakeio("file"))
      uploaded_file.open
      uploaded_file.storage.expects(:open).never
      downloaded = uploaded_file.download
      assert_match "file", downloaded.read
    end

    it "applies extension from #id" do
      uploaded_file = @uploader.upload(fakeio, location: "foo.jpg")
      assert_match /\.jpg$/, uploaded_file.download.path
    end

    it "applies extension from #original_filename" do
      uploaded_file = @uploader.upload(fakeio(filename: "foo.jpg"), location: "foo")
      assert_match /\.jpg$/, uploaded_file.download.path
    end

    it "forwards any options to Storage#open" do
      uploaded_file = @uploader.upload(fakeio)
      uploaded_file.expects(:open).with(foo: "bar")
      uploaded_file.download(foo: "bar")
    end

    it "yields the tempfile if block is given" do
      uploaded_file = @uploader.upload(fakeio)
      uploaded_file.download { |tempfile| @block = tempfile }
      assert_instance_of Tempfile, @block
    end

    it "returns the block return value" do
      uploaded_file = @uploader.upload(fakeio)
      result = uploaded_file.download { |tempfile| "result" }
      assert_equal "result", result
    end

    it "closes and deletes the tempfile after the block" do
      uploaded_file = @uploader.upload(fakeio)
      tempfile = uploaded_file.download { |tempfile| refute tempfile.closed?; tempfile }
      assert tempfile.closed?
      assert_nil tempfile.path
    end

    it "deletes the Tempfile in case of exceptions" do
      tempfile = Tempfile.new("")
      Tempfile.stubs(:new).returns(tempfile)
      assert_raises(Shrine::FileNotFound) { uploaded_file.download }
      assert tempfile.closed?
      assert_nil tempfile.path
    end

    it "rewinds the uploaded file and keeps it open if it was already open" do
      uploaded_file = @uploader.upload(fakeio("content"))
      uploaded_file.open
      uploaded_file.storage.expects(:open).never
      tempfile = uploaded_file.download
      assert_equal "content", tempfile.read
      assert_equal "content", uploaded_file.read
    end

    it "propagates exceptions that occured when creating the Tempfile" do
      Tempfile.stubs(:new).raises(Errno::EMFILE) # too many open files
      assert_raises(Errno::EMFILE) { uploaded_file.download }
    end
  end

  describe "#stream" do
    it "opens and closes the file after streaming if it was not open" do
      uploaded_file = @uploader.upload(fakeio("content"))
      uploaded_file.stream(destination = StringIO.new)
      assert_equal "content", destination.string
      uploaded_file.storage.expects(:open)
      uploaded_file.to_io
    end

    it "rewinds the uploaded file and keeps it open if it was already open" do
      uploaded_file = @uploader.upload(fakeio("content"))
      uploaded_file.open
      uploaded_file.storage.expects(:open).never
      uploaded_file.stream(destination = StringIO.new)
      assert_equal "content", destination.string
      assert_equal "content", uploaded_file.read
    end
  end

  describe "#replace" do
    it "uploads another file to the same location" do
      uploaded_file = @uploader.upload(fakeio("file"))
      new_uploaded_file = uploaded_file.replace(fakeio("replaced"))

      assert_equal uploaded_file.id, new_uploaded_file.id
      assert_equal "replaced", new_uploaded_file.read
      assert_equal 8, new_uploaded_file.size
    end
  end

  describe "#delete" do
    it "delegates to underlying storage" do
      uploaded_file = @uploader.upload(fakeio)
      uploaded_file.delete
      refute uploaded_file.exists?
    end
  end

  describe "#to_io" do
    it "returns the underlying IO" do
      uploaded_file = @uploader.upload(fakeio)
      assert_instance_of StringIO, uploaded_file.to_io
      assert_equal uploaded_file.to_io, uploaded_file.to_io
    end
  end

  describe "#data" do
    it "returns uploaded file data hash" do
      uploaded_file = uploaded_file(
        id:       "foo",
        storage:  :store,
        metadata: { "foo" => "bar" },
      )

      assert_equal Hash[
        "id"       => "foo",
        "storage"  => "store",
        "metadata" => { "foo" => "bar" },
      ], uploaded_file.data
    end
  end

  it "exposes #storage and #uploader" do
    uploaded_file = uploaded_file({})
    assert_instance_of Shrine::Storage::Memory, uploaded_file.storage
    assert_instance_of uploaded_file.shrine_class, uploaded_file.uploader
  end

  it "implements #to_json" do
    uploaded_file = uploaded_file(id: "foo", storage: :store, metadata: {})
    assert_equal '{"id":"foo","storage":"store","metadata":{}}', uploaded_file.to_json
    assert_equal '{"thumb":{"id":"foo","storage":"store","metadata":{}}}', {thumb: uploaded_file}.to_json
  end

  it "implements equality" do
    assert_equal uploaded_file, uploaded_file
    assert_equal uploaded_file(metadata: { "foo" => "foo" }), uploaded_file(metadata: { "bar" => "bar" })
    refute_equal uploaded_file(id: "foo"), uploaded_file(id: "bar")
    refute_equal uploaded_file(storage: :store), uploaded_file(storage: :cache)
    refute_equal StringIO.new, uploaded_file
  end

  it "implements hash equality" do
    assert_equal 1, Set.new([uploaded_file, uploaded_file]).size
    assert_equal 2, Set.new([uploaded_file(id: "foo"), uploaded_file(id: "bar")]).size
    assert_equal 2, Set.new([uploaded_file(storage: :store), uploaded_file(storage: :cache)]).size
  end

  it "has custom .inspect" do
    assert_equal "#{@shrine}::UploadedFile", uploaded_file.class.inspect
  end

  it "has custom #inspect" do
    assert_equal %(#<#{@shrine}::UploadedFile storage=:store id="foo" metadata={"bar"=>"quux"}>),
                 uploaded_file(id: "foo", storage: :store, metadata: { "bar" => "quux" }).inspect
  end
end
