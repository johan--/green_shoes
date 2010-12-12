class Shoes
  module Mod
    def set_margin
      @margin ||= [0, 0, 0, 0]
      @margin = [@margin, @margin, @margin, @margin] if @margin.is_a? Integer
      margin_left, margin_top, margin_right, margin_bottom = @margin
      @margin_left ||= margin_left
      @margin_top ||= margin_top
      @margin_right ||= margin_right
      @margin_bottom ||= margin_bottom
    end

    attr_reader :margin_left, :margin_top, :margin_right, :margin_bottom
  end
  
  module Mod2
    def init_app_vars
      @contents, @mccs, @mrcs, @mmcs, @mlcs, @shcs, @mcs, @order = 
        [], [], [], [], [], [], [], []
      @cmask = nil
      @mouse_button, @mouse_pos = 0, [0, 0]
      @fill, @stroke = black, black
    end
  end

  class App
    def basic_attributes args={}
      default = {left: 0, top: 0, width: 0, height: 0, angle: 0, curve: 0}
      default.merge args
    end

    def slot_attributes args={}
      default = {left: nil, top: nil, width: 1.0, height: 0}
      default.merge args
    end

    def create_tmp_png surface
      surface.write_to_png TMP_PNG_FILE
      Gtk::Image.new TMP_PNG_FILE
    end
    
    def make_link_index msg
      start, links = 0, []
      msg.each do |e|
        len = e.to_s.gsub(/<\/.*?>/, '').gsub(/<.*?>/, '').length
        (links << e; e.index = [start, start + len - 1]) if e.is_a? Link
        start += len
      end
      links
    end
    
    def make_link_pos links, layout, line_height
      links.each do |e|
        e.pos = [layout.index_to_pos(e.index[0]).x / Pango::SCALE, layout.index_to_pos(e.index[0]).y / Pango::SCALE]
        e.pos << (layout.index_to_pos(e.index[1]).x / Pango::SCALE + line_height / 2) << (layout.index_to_pos(e.index[1]).y / Pango::SCALE)
        e.pos << line_height
      end
    end
  end

  def self.contents_alignment slot
    x, y = slot.left.to_i, slot.top.to_i
    max = Struct.new(:top, :height).new
    max.top, max.height = y, 0
    slot_height = 0

    slot.contents.each do |ele|
      if ele.is_a? ShapeBase
        ele.hide if slot.masked
        next
      end
      tmp = max
      max = ele.positioning x, y, max
      x, y = ele.left + ele.width, ele.top + ele.height
      slot_height += max.height unless max == tmp
    end
    slot_height
  end

  def self.repaint_all slot
    return if slot.masked
    slot.contents.each do |ele|
      next if ele.is_a? ShapeBase
      ele.is_a?(Basic) ? ele.move2(ele.left + ele.margin_left, ele.top + ele.margin_top) : repaint_all(ele)
    end
  end

  def self.repaint_all_by_order app
    app.order.each do |e|
      if e.real and !e.is_a?(Pattern) and !e.hided
        app.canvas.remove e.real
        app.canvas.put e.real, e.left, e.top
      end
    end
  end
  
  def self.call_back_procs app
    init_contents app.cslot.contents
    app.cslot.width, app.cslot.height = app.width, app.height
    contents_alignment app.cslot
    repaint_all app.cslot
    repaint_all_by_order app
    mask_control app
    true
  end

  def self.init_contents contents
    contents.each do |ele|
      next unless ele.is_a? Slot
      ele.initials.each do |k, v|
        ele.send "#{k}=", v
      end
    end
  end

  def self.mouse_click_control app
    app.mccs.each do |e|
      e.click_proc.call if mouse_on? e
    end
  end
  
  def self.mouse_release_control app
    app.mrcs.each do |e|
      e.release_proc.call if mouse_on? e
    end
  end

  def self.mouse_motion_control app
    app.mmcs.each do |blk|
      blk[*app.win.pointer]
    end
  end

  def self.mouse_link_control app
    app.mlcs.each do |tb|
      link_proc,  = mouse_on_link(tb, app)
      link_proc.call if link_proc
    end
  end
  
  def self.set_cursor_type app
    app.mccs.each do |e|
      e.real.window.cursor = ARROW if e.real.window
      (e.real.window.cursor = HAND; return) if mouse_on? e
    end
    
    app.mlcs.each do |tb|
      tb.text = tb.text unless tb.real
      tb.real.window.cursor = ARROW if tb.real.window
      if ret = mouse_on_link(tb, app)
        tb.real.window.cursor = HAND
        unless tb.links[ret[1]].link_hover
          markup = tb.args[:markup].gsub(app.linkhover_style, app.link_style)
          links = markup.mindex  app.link_style
          n = links[ret[1]]
          tb.text = markup[0...n] + markup[n..-1].sub(app.link_style, app.linkhover_style)
          tb.links.each{|e| e.link_hover = false}
          tb.links[ret[1]].link_hover = true
        end
        return
      end
      if tb.links.map(&:link_hover).include? true
        tb.text = tb.args[:markup].gsub(app.linkhover_style, app.link_style)
        tb.links.each{|e| e.link_hover = false}
      end
    end
  end
  
  def self.mouse_on? e
    mouse_x, mouse_y = e.real.pointer
    (0..e.width).include?(mouse_x) and (0..e.height).include?(mouse_y)
  end

  def self.mouse_on_link tb, app
    mouse_x, mouse_y = app.win.pointer
    mouse_x -= tb.left
    mouse_y -= tb.top
    tb.links.each_with_index do |e, n|
      return [e.link_proc, n] if ((0..tb.width).include?(mouse_x) and (e.pos[1]..(e.pos[3]+e.pos[4])).include?(mouse_y) \
        and !((0..e.pos[0]).include?(mouse_x) and (e.pos[1]..(e.pos[1]+e.pos[4])).include?(mouse_y)) \
        and !((e.pos[2]..tb.width).include?(mouse_x) and (e.pos[3]..(e.pos[3]+e.pos[4])).include?(mouse_y)) \
      )
    end
    return false
  end

  def self.size_allocated? app
    not (app.width_pre == app.width and app.height_pre == app.height)
  end

  def self.show_hide_control app
    app.shcs.each do |e|
      case
        when(!e.shows and !e.hided)
          e.remove
          e.hided = true
        when(e.shows and e.hided)
          e.hided = false
          e.is_a?(Pattern) ? e.move2(e.left, e.top) : app.canvas.put(e.real, e.left, e.top)
        else
      end
    end
  end

  def self.mask_control app
    app.mcs.each do |m|
      w, h = m.parent.width, m.parent.height
      w = app.width if w.zero?
      h = app.height if h.zero?
      surface = Cairo::ImageSurface.new Cairo::FORMAT_ARGB32, w, h
      context = Cairo::Context.new surface
      context.push_group do
        m.parent.contents.each do |ele|
          x, y = ele.left - m.parent.left, ele.top - m.parent.top
          context.translate x, y
          context.set_source_pixbuf ele.real.pixbuf
          context.paint
          context.translate -x, -y
        end
      end

      sf = Cairo::ImageSurface.new Cairo::FORMAT_ARGB32, w, h
      ct = Cairo::Context.new surface
      pat = ct.push_group nil, false do
        m.contents.each do |ele|
          if ele.is_a? TextBlock
            ele.height = h
            ele.text = ele.args[:markup]
          end
          x, y = ele.left - m.parent.left, ele.top - m.parent.top
          ct.translate x, y
          ct.set_source_pixbuf ele.real.pixbuf
          ct.paint
          ct.translate -x, -y
        end
      end

      context.mask pat
      img = app.create_tmp_png surface
      app.canvas.put img, 0, 0
      img.show_now
    end
  end
end
