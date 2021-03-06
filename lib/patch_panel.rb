# Software patch-panel.
class PatchPanel < Trema::Controller
  def start(_args)
    @patch = Hash.new { |h,k| h[k]=[] }
    @m_patch = Hash.new { |h,k| h[k]=[] }
    logger.info 'PatchPanel started.'
  end

  def switch_ready(dpid)
    logger.info 'dpid = #{dpid}'
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
    @patch[dpid] << [port_a, port_b].sort if add_flow_entries dpid, port_a, port_b
  end

  def delete_patch(dpid, port_a, port_b)
    @patch[dpid].delete([port_a, port_b].sort) if delete_flow_entries dpid, port_a, port_b
  end

  def create_mirror_patch(dpid, port, mirror)
    @m_patch[dpid] << [port, mirror] if add_flow_mirror_entries dpid, port, mirror
  end

  def delete_mirror_patch(dpid, port, mirror)
    @m_patch[dpid].delete([port, mirror]) if delete_flow_mirror_entries dpid, port, mirror
  end

  def print_patch_mirror(dpid)
    ret = Array.new()
    ret << @patch
    ret << @m_patch
    return ret
  end

  private

  def add_flow_entries(dpid, port_a, port_b)
    @patch[dpid].each do |ports|
      return false if ports.include?(port_a)
      return false if ports.include?(port_b)
    end
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port_a),
                      actions: SendOutPort.new(port_b))
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port_b),
                      actions: SendOutPort.new(port_a))
    return true
  end

  def delete_flow_entries(dpid, port_a, port_b)
    is_no_entry = true
    @patch[dpid].each do |ports|
      is_no_entry = false if ports == [port_a, port_b].sort
    end
    return false if is_no_entry
    send_flow_mod_delete(dpid, match: Match.new(in_port: port_a))
    send_flow_mod_delete(dpid, match: Match.new(in_port: port_b))
    del = nil
    @m_patch[dpid].each do |ports|
      del = ports if port_a == ports[0]
    end
    @m_patch[dpid].delete(del) if del
    del = nil
    @m_patch[dpid].each do |ports|
      del = ports if port_b == ports[0]
    end
    @m_patch[dpid].delete(del) if del
    return true
  end

  def add_flow_mirror_entries(dpid, port, mirror)
    @m_patch[dpid].each do |ports|
      return false if ports[0] == port
    end
    port_src = nil
    @patch[dpid].each do |port_a, port_b|
      port_src = port_a if port_b == port
      port_src = port_b if port_a == port
    end
    return false if port_src == nil
    send_flow_mod_delete(dpid, match: Match.new(in_port: port_src))
    send_flow_mod_delete(dpid, match: Match.new(in_port: port))
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port_src),
                      actions: [
                          SendOutPort.new(port),
                          SendOutPort.new(mirror),
                      ])
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port),
                      actions: [
                          SendOutPort.new(port_src),
                          SendOutPort.new(mirror),
                      ])
    return true
  end

  def delete_flow_mirror_entries(dpid, port, mirror)
    is_no_entry = true
    @m_patch[dpid].each do |ports|
      is_no_entry = false if ports == [port, mirror]
    end
    return false if is_no_entry
    port_src = nil
    @patch[dpid].each do |port_a, port_b|
      port_src = port_a if port_b == port
      port_src = port_b if port_a == port
    end
    send_flow_mod_delete(dpid, match: Match.new(in_port: port_src))
    send_flow_mod_delete(dpid, match: Match.new(in_port: port))
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port_src),
                      actions: SendOutPort.new(port))
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port),
                      actions: SendOutPort.new(port_src))
    return true
  end


end
