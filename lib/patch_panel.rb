# Software patch-panel.
class PatchPanel < Trema::Controller
  def start(_args)
    @patch = Hash.new { |h,k| h[k]=[] }
    @m_patch = Hash.new { |h,k| h[k]=[] }
    logger.info 'PatchPanel started.'
  end

  def switch_ready(dpid)
    @patch[dpid].each do |port_a, port_b|
      delete_flow_entries dpid, port_a, port_b
      add_flow_entries dpid, port_a, port_b
    end
    @m_patch[dpid].each do |port, mirror|
      delete_flow_mirror_entries dpid, port, mirror
      add_flow_mirror_entries dpid, port, mirror
    end
  end

  def create_patch(dpid, port_a, port_b)
    add_flow_entries dpid, port_a, port_b
  end

  def delete_patch(dpid, port_a, port_b)
    delete_flow_entries dpid, port_a, port_b
  end

  def create_mirror_patch(dpid, port, mirror)
    add_flow_mirror_entries dpid, port, mirror
  end

  def delete_mirror_patch(dpid, port, mirror)
    delete_flow_mirror_entries dpid, port, mirror
  end

  def print_patch_mirror(dpid)
    p "Patch list: (port <=> port)"
    @patch[dpid].each do |port_a, port_b|
      print(port_a, " <=> ", port_b, "\n")
    end
    p "Mirror list: (port => mirror)"
    @m_patch[dpid].each do |port, mirror|
      print(port, " => ", mirror, "\n")
    end
  end

  private

  def add_flow_entries(dpid, port_a, port_b)
    @patch[dpid].each do |ports|
      return if ports == [port_a, port_b].sort
    end
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port_a),
                      actions: SendOutPort.new(port_b))
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port_b),
                      actions: SendOutPort.new(port_a))
    @patch[dpid] << [port_a, port_b].sort
  end

  def delete_flow_entries(dpid, port_a, port_b)
    is_no_entry = true
    @patch[dpid].each do |ports|
      is_no_entry = false if ports == [port_a, port_b].sort
    end
    return if is_no_entry
    send_flow_mod_delete(dpid,
                         match: Match.new(in_port: port_a),
                         actions: SendOutPort.new(port_b))
    send_flow_mod_delete(dpid,
                         match: Match.new(in_port: port_b),
                         actions: SendOutPort.new(port_a))
    @patch[dpid].delete([port_a, port_b].sort)
  end

  def add_flow_mirror_entries(dpid, port, mirror)
    @m_patch[dpid].each do |ports|
      return if ports == [port, mirror]
    end
    port_src = nil
    @patch[dpid].each do |port_a, port_b|
      port_src = port_a if port_b == port
      port_src = port_b if port_a == port
    end
    return if port_src == nil
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port_src),
                      actions: SendOutPort.new(mirror))
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port),
                      actions: SendOutPort.new(mirror))
    @m_patch[dpid] << [port, mirror]
  end

  def delete_flow_mirror_entries(dpid, port, mirror)
    is_no_entry = true
    @m_patch[dpid].each do |ports|
      is_no_entry = false if ports == [port, mirror]
    end
    return if is_no_entry
    port_src = nil
    @patch[dpid].each do |port_a, port_b|
      port_src = port_a if port_b == port
      port_src = port_b if port_a == port
    end
    send_flow_mod_delete(dpid,
                         match: Match.new(in_port: port_src),
                         actions: SendOutPort.new(mirror))
    send_flow_mod_delete(dpid,
                         match: Match.new(in_port: port),
                         actions: SendOutPort.new(mirror))
    @m_patch[dpid].delete([port, mirror])
  end


end
