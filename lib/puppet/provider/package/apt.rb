Puppet::Type.type(:package).provide :apt, :parent => :dpkg, :source => :dpkg do
  # Provide sorting functionality
  include Puppet::Util::Package

  desc "Package management via `apt-get`.

    This provider supports the `install_options` attribute, which allows command-line flags to be passed to apt-get.
    These options should be specified as an array where each element is either a
     string or a hash."

  has_feature :versionable, :install_options, :virtual_packages

  commands :aptget => "/usr/bin/apt-get"
  commands :aptcache => "/usr/bin/apt-cache"
  commands :preseed => "/usr/bin/debconf-set-selections"

  defaultfor :osfamily => :debian

  ENV['DEBIAN_FRONTEND'] = "noninteractive"

  # disable common apt helpers to allow non-interactive package installs
  ENV['APT_LISTBUGS_FRONTEND'] = "none"
  ENV['APT_LISTCHANGES_FRONTEND'] = "none"

  def self.defaultto_allow_virtual
    false
  end

  # A derivative of DPKG; this is how most people actually manage
  # Debian boxes, and the only thing that differs is that it can
  # install packages from remote sites.

  def checkforcdrom
    have_cdrom = begin
                   !!(File.read("/etc/apt/sources.list") =~ /^[^#]*cdrom:/)
                 rescue
                   # This is basically pathological...
                   false
                 end

    if have_cdrom and @resource[:allowcdrom] != :true
      raise Puppet::Error,
        _("/etc/apt/sources.list contains a cdrom source; not installing.  Use 'allowcdrom' to override this failure.")
    end
  end

  # Install a package using 'apt-get'.  This function needs to support
  # installing a specific version.
  def install
    self.run_preseed if @resource[:responsefile]
    should = @resource[:ensure]

    checkforcdrom
    cmd = %w{-q -y}

    config = @resource[:configfiles]
    if config
      if config == :keep
        cmd << "-o" << 'DPkg::Options::=--force-confold'
      else
        cmd << "-o" << 'DPkg::Options::=--force-confnew'
      end
    end

    str = @resource[:name]
    case should
    when true, false, Symbol
      # pass
    else
      # Add the package version and --force-yes option
      str += "=#{should}"
      cmd << "--force-yes"
    end

    cmd += install_options if @resource[:install_options]
    cmd << :install << str

    self.unhold if self.properties[:mark] == :hold
    begin
      aptget(*cmd)
    ensure
      self.hold if @resource[:mark] == :hold
    end
  end

  # What's the latest package version available?
  def latest
    output = aptcache :policy,  @resource[:name]

    if output =~ /Candidate:\s+(\S+)\s/
      return $1
    else
      self.err _("Could not find latest version")
      return nil
    end
  end

  #
  # preseeds answers to dpkg-set-selection from the "responsefile"
  #
  def run_preseed
    response = @resource[:responsefile]
    if response && Puppet::FileSystem.exist?(response)
      self.info(_("Preseeding %{response} to debconf-set-selections") % { response: response })

      preseed response
    else
      self.info _("No responsefile specified or non existent, not preseeding anything")
    end
  end

  def uninstall
    self.run_preseed if @resource[:responsefile]
    args = ['-y', '-q']
    args << '--allow-change-held-packages' if self.properties[:mark] == :hold
    args << :remove << @resource[:name]
    aptget(*args)
  end

  def purge
    self.run_preseed if @resource[:responsefile]
    args = ['-y', '-q']
    args << '--allow-change-held-packages' if self.properties[:mark] == :hold
    args << :remove << '--purge' << @resource[:name]
    aptget(*args)
    # workaround a "bug" in apt, that already removed packages are not purged
    super
  end

  def install_options
    join_options(@resource[:install_options])
  end
end
