# Software patch-panel.
class PatchPanel < Trema::Controller
  def start(_args)
    @patch = Hash.new { |h,k| h[k]=[] }
    @m_patch = Hash.new { [] }
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
    @patch[dpid] << [port_a, port_b].sort
  end

  def delete_patch(dpid, port_a, port_b)
    delete_flow_entries dpid, port_a, port_b
    @patch[dpid] -= [port_a, port_b].sort
  end

  def create_mirror_patch(dpid, port, mirror)
    add_flow_mirror_entries dpid, port, mirror
    @m_patch[dpid] << [port, mirror]
  end

  def delete_mirror_patch(dpid, port, mirror)
    delete_flow_mirror_entries dpid, port, mirror
    @m_patch[dpid] -= [port, mirror]
  end

  def print_patch_mirror(dpid)
    p "Patch list:"
    p @patch[dpid]
    p "Mirror list:"
    p @m_patch[dpid]
  end

  private

  def add_flow_entries(dpid, port_a, port_b)
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port_a),
                      actions: SendOutPort.new(port_b))
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port_b),
                      actions: SendOutPort.new(port_a))
  end

  def delete_flow_entries(dpid, port_a, port_b)
    send_flow_mod_delete(dpid,
                         match: Match.new(in_port: port_a),
                         actions: SendOutPort.new(port_b))
    send_flow_mod_delete(dpid,
                         match: Match.new(in_port: port_b),
                         actions: SendOutPort.new(port_a))
  end

  def add_flow_mirror_entries(dpid, port, mirror)
    send_flow_mod_add(dpid,
                      match: Match.new(out_port: port),
                      actions: SendOutPort.new(mirror))
  end

  def delete_flow_mirror_entries(dpid, port, mirror)
    send_flow_mod_delete(dpid,
                         match: Match.new(out_port: port),
                         actions: SendOutPort.new(mirror))
  end


end
