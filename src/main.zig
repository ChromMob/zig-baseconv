const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const Cell = vaxis.Cell;
const Style = vaxis.Style;
const Color = vaxis.Color;

// ─── Color Palette ─────────────────────────────────────────────────────────

const accent_color = Color{ .rgb = .{ 0x7A, 0x9E, 0x9F } };
const header_bg = Color{ .rgb = .{ 0x1A, 0x1A, 0x2E } };
const panel_bg = Color{ .rgb = .{ 0x16, 0x16, 0x20 } };
const field_bg = Color{ .rgb = .{ 0x1E, 0x1E, 0x2E } };
const focused_border = Color{ .rgb = .{ 0x89, 0xB4, 0xFA } };
const text_color = Color{ .rgb = .{ 0xCD, 0xD6, 0xF4 } };
const dim_text = Color{ .rgb = .{ 0x6C, 0x70, 0x86 } };
const error_color = Color{ .rgb = .{ 0xF3, 0x8B, 0xA8 } };
const success_color = Color{ .rgb = .{ 0xA6, 0xE3, 0xA1 } };
const history_bg = Color{ .rgb = .{ 0x13, 0x13, 0x1A } };

// ─── ASCII Character Table ─────────────────────────────────────────────────
// Provides stable pointers for single-character graphemes
var ascii_chars: [128][1:0]u8 = blk: {
    var table: [128][1:0]u8 = undefined;
    for (0..128) |i| {
        table[i] = .{@intCast(i)};
    }
    break :blk table;
};

fn asciiGrapheme(byte: u8) []const u8 {
    if (byte < 128) return &ascii_chars[byte];
    return "?";
}
const info_bg = Color{ .rgb = .{ 0x1E, 0x1E, 0x28 } };
const highlight_color = Color{ .rgb = .{ 0xF9, 0xE2, 0xAF } };

// ─── Configuration ─────────────────────────────────────────────────────────

const BaseConfig = struct {
    name: []const u8,
    base: u8,
    prefix: []const u8,
};

const base_configs = [_]BaseConfig{
    .{ .name = "Binary", .base = 2, .prefix = "0b" },
    .{ .name = "Octal", .base = 8, .prefix = "0o" },
    .{ .name = "Decimal", .base = 10, .prefix = "" },
    .{ .name = "Hexadecimal", .base = 16, .prefix = "0x" },
};

const max_input_len = 256;

// ─── History Entry ─────────────────────────────────────────────────────────

const HistoryEntry = struct {
    base: u8,
    input: []const u8,
};

// ─── Input Field ───────────────────────────────────────────────────────────

const InputField = struct {
    buffer: [max_input_len]u8 = undefined,
    len: usize = 0,
    cursor: usize = 0,

    fn text(self: *InputField) []const u8 {
        return self.buffer[0..self.len];
    }

    fn insert(self: *InputField, ch: u8) void {
        if (self.len >= max_input_len) return;
        std.mem.copyBackwards(u8, self.buffer[self.cursor + 1 .. self.len + 1], self.buffer[self.cursor..self.len]);
        self.buffer[self.cursor] = ch;
        self.cursor += 1;
        self.len += 1;
    }

    fn insertSlice(self: *InputField, slice: []const u8) void {
        for (slice) |ch| self.insert(ch);
    }

    fn backspace(self: *InputField) void {
        if (self.cursor == 0) return;
        std.mem.copyForwards(u8, self.buffer[self.cursor - 1 .. self.len - 1], self.buffer[self.cursor..self.len]);
        self.cursor -= 1;
        self.len -= 1;
    }

    fn deleteChar(self: *InputField) void {
        if (self.cursor >= self.len) return;
        std.mem.copyForwards(u8, self.buffer[self.cursor .. self.len - 1], self.buffer[self.cursor + 1 .. self.len]);
        self.len -= 1;
    }

    fn moveLeft(self: *InputField) void {
        if (self.cursor > 0) self.cursor -= 1;
    }

    fn moveRight(self: *InputField) void {
        if (self.cursor < self.len) self.cursor += 1;
    }

    fn moveHome(self: *InputField) void {
        self.cursor = 0;
    }

    fn moveEnd(self: *InputField) void {
        self.cursor = self.len;
    }

    fn clear(self: *InputField) void {
        self.len = 0;
        self.cursor = 0;
    }

    fn deleteWordBefore(self: *InputField) void {
        if (self.cursor == 0) return;
        var end = self.cursor;
        while (end > 0 and self.buffer[end - 1] == ' ') {
            end -= 1;
        }
        while (end > 0 and self.buffer[end - 1] != ' ') {
            end -= 1;
        }
        std.mem.copyForwards(u8, self.buffer[end..self.len - (self.cursor - end)], self.buffer[self.cursor..self.len]);
        self.len -= self.cursor - end;
        self.cursor = end;
    }
};

// ─── App State ─────────────────────────────────────────────────────────────

const App = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}) = .{},
    
    // Standard base inputs
    inputs: [4]InputField = .{ .{}, .{}, .{}, .{} },
    
    // Custom base
    custom_base_input: InputField = .{},
    custom_base: u8 = 36,
    custom_value_input: InputField = .{},
    
    // Focus management
    focused_field: usize = 0,
    total_fields: usize = 6,
    
    // History
    history: std.ArrayList(HistoryEntry),
    show_history: bool = false,
    
    // Status message
    status_msg: ?[]const u8 = null,
    status_time: i64 = 0,
    
    // Blink timer
    blink_visible: bool = true,
    last_blink: i64 = 0,

    pub fn init(self: *App) !void {
        const now = std.time.milliTimestamp();
        self.* = .{
            .gpa = .{},
            .inputs = .{ .{}, .{}, .{}, .{} },
            .custom_base_input = .{},
            .custom_base = 36,
            .custom_value_input = .{},
            .focused_field = 0,
            .total_fields = 6,
            .history = .empty,
            .show_history = false,
            .status_msg = null,
            .status_time = 0,
            .blink_visible = true,
            .last_blink = now,
        };
        self.custom_base_input.insertSlice("36");
    }

    pub fn deinit(self: *App) void {
        const alloc = self.allocator();
        for (self.history.items) |entry| {
            alloc.free(entry.input);
        }
        self.history.deinit(alloc);
        _ = self.gpa.deinit();
    }

    fn allocator(self: *App) std.mem.Allocator {
        return self.gpa.allocator();
    }

    fn setStatus(self: *App, msg: []const u8) void {
        self.status_msg = msg;
        self.status_time = std.time.milliTimestamp();
    }

    fn clearStatusIfExpired(self: *App) void {
        if (self.status_msg) |_| {
            if (std.time.milliTimestamp() - self.status_time > 3000) {
                self.status_msg = null;
            }
        }
    }

    fn updateBlink(self: *App) void {
        const now = std.time.milliTimestamp();
        if (now - self.last_blink > 530) {
            self.blink_visible = !self.blink_visible;
            self.last_blink = now;
        }
    }

    fn parseValue(_: *App, text: []const u8, base: u8) ?u128 {
        if (text.len == 0) return null;
        
        var result: u128 = 0;
        for (text) |c| {
            const digit = switch (c) {
                '0'...'9' => c - '0',
                'a'...'z' => c - 'a' + 10,
                'A'...'Z' => c - 'A' + 10,
                ' ', '_' => continue,
                else => return null,
            };
            if (digit >= base) return null;
            if (result > std.math.maxInt(u128) / @as(u128, base)) return null;
            result = result * base + digit;
        }
        return result;
    }

    fn formatValue(_: *App, value: u128, base: u8, buf: []u8) ![]const u8 {
        if (value == 0) return "0";
        
        var i: usize = buf.len;
        var v = value;
        while (v > 0) {
            i -= 1;
            const digit = v % base;
            buf[i] = if (digit < 10) '0' + @as(u8, @intCast(digit)) else 'A' + @as(u8, @intCast(digit)) - 10;
            v /= base;
        }
        return buf[i..];
    }

    fn updateAllFields(self: *App, source_idx: usize) void {
        const field = if (source_idx < 4)
            &self.inputs[source_idx]
        else if (source_idx == 4)
            &self.custom_value_input
        else
            &self.custom_base_input;

        const base = if (source_idx < 4)
            base_configs[source_idx].base
        else if (source_idx == 4)
            self.custom_base
        else
            10;

        if (source_idx == 5) {
            if (self.parseValue(self.custom_base_input.text(), 10)) |new_base| {
                if (new_base >= 2 and new_base <= 36) {
                    self.custom_base = @intCast(new_base);
                    self.updateAllFields(4);
                }
            }
            return;
        }
        
        if (field.len == 0) {
            for (0..4) |i| {
                if (i != source_idx) self.inputs[i].clear();
            }
            if (source_idx != 4) self.custom_value_input.clear();
            return;
        }

        const value = self.parseValue(field.text(), base);
        if (value == null) return;

        var buf: [128]u8 = undefined;
        
        for (0..4) |i| {
            if (i == source_idx) continue;
            if (value) |v| {
                const formatted = self.formatValue(v, base_configs[i].base, &buf) catch continue;
                self.inputs[i].clear();
                self.inputs[i].insertSlice(formatted);
            }
        }
        
        if (source_idx != 4) {
            if (value) |v| {
                const formatted = self.formatValue(v, self.custom_base, &buf) catch return;
                self.custom_value_input.clear();
                self.custom_value_input.insertSlice(formatted);
            }
        } else {
            for (0..4) |i| {
                if (value) |v| {
                    const formatted = self.formatValue(v, base_configs[i].base, &buf) catch continue;
                    self.inputs[i].clear();
                    self.inputs[i].insertSlice(formatted);
                }
            }
        }

        // Add to history
        const text = field.text();
        if (self.history.items.len == 0 or 
            !std.mem.eql(u8, self.history.items[self.history.items.len - 1].input, text)) {
            if (self.history.items.len > 50) {
                const old = self.history.orderedRemove(0);
                self.allocator().free(old.input);
            }
            const copy = self.allocator().dupe(u8, text) catch return;
            self.history.append(self.allocator(), .{
                .base = base,
                .input = copy,
            }) catch {};
        }
    }

    fn copyCurrentField(self: *App) void {
        const text = if (self.focused_field < 4)
            self.inputs[self.focused_field].text()
        else if (self.focused_field == 4)
            self.custom_value_input.text()
        else
            self.custom_base_input.text();
        
        if (text.len == 0) {
            self.setStatus("Nothing to copy!");
            return;
        }

        self.setStatus("Copied to clipboard (simulated)!");
    }

    fn clearAll(self: *App) void {
        for (0..4) |i| {
            self.inputs[i].clear();
        }
        self.custom_value_input.clear();
        self.custom_base_input.clear();
        self.custom_base_input.insertSlice("36");
        self.custom_base = 36;
        self.setStatus("Cleared all fields");
    }

    fn getFocusedField(self: *App) *InputField {
        return if (self.focused_field < 4)
            &self.inputs[self.focused_field]
        else if (self.focused_field == 4)
            &self.custom_value_input
        else
            &self.custom_base_input;
    }

    // ─── Widget Interface ──────────────────────────────────────────────────

    pub fn widget(self: *App) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = App.typeErasedEventHandler,
            .drawFn = App.typeErasedDrawFn,
        };
    }

    fn typeErasedEventHandler(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *App = @ptrCast(@alignCast(ptr));
        
        switch (event) {
            .init => {
                try ctx.requestFocus(self.widget());
                try ctx.tick(530, self.widget());
            },
            .tick => {
                self.updateBlink();
                ctx.redraw = true;
                try ctx.tick(530, self.widget());
            },
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    self.copyCurrentField();
                    ctx.redraw = true;
                    return;
                }
                if (key.matches('h', .{ .ctrl = true })) {
                    self.show_history = !self.show_history;
                    ctx.redraw = true;
                    return;
                }
                if (key.matches('x', .{ .ctrl = true })) {
                    self.clearAll();
                    ctx.redraw = true;
                    return;
                }
                if (key.matches('q', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
                }
                if (key.matches(vaxis.Key.tab, .{})) {
                    self.focused_field = (self.focused_field + 1) % self.total_fields;
                    ctx.redraw = true;
                    return;
                }
                if (key.matches(vaxis.Key.tab, .{ .shift = true })) {
                    self.focused_field = if (self.focused_field == 0) self.total_fields - 1 else self.focused_field - 1;
                    ctx.redraw = true;
                    return;
                }
                if (key.matches(vaxis.Key.down, .{})) {
                    self.focused_field = @min(self.focused_field + 1, self.total_fields - 1);
                    ctx.redraw = true;
                    return;
                }
                if (key.matches(vaxis.Key.up, .{})) {
                    self.focused_field = if (self.focused_field == 0) 0 else self.focused_field - 1;
                    ctx.redraw = true;
                    return;
                }

                const field = self.getFocusedField();
                const old_len = field.len;

                if (key.matches(vaxis.Key.backspace, .{})) {
                    field.backspace();
                } else if (key.matches(vaxis.Key.delete, .{}) or key.matches('d', .{ .ctrl = true })) {
                    field.deleteChar();
                } else if (key.matches(vaxis.Key.left, .{}) or key.matches('b', .{ .ctrl = true })) {
                    field.moveLeft();
                    ctx.redraw = true;
                    return;
                } else if (key.matches(vaxis.Key.right, .{}) or key.matches('f', .{ .ctrl = true })) {
                    field.moveRight();
                    ctx.redraw = true;
                    return;
                } else if (key.matches('a', .{ .ctrl = true }) or key.matches(vaxis.Key.home, .{})) {
                    field.moveHome();
                    ctx.redraw = true;
                    return;
                } else if (key.matches('e', .{ .ctrl = true }) or key.matches(vaxis.Key.end, .{})) {
                    field.moveEnd();
                    ctx.redraw = true;
                    return;
                } else if (key.matches('w', .{ .ctrl = true })) {
                    field.deleteWordBefore();
                } else if (key.matches('k', .{ .ctrl = true })) {
                    field.len = field.cursor;
                } else if (key.matches('u', .{ .ctrl = true })) {
                    std.mem.copyForwards(u8, field.buffer[0..field.len - field.cursor], field.buffer[field.cursor..field.len]);
                    field.len -= field.cursor;
                    field.cursor = 0;
                } else if (key.text) |text| {
                    for (text) |ch| {
                        if (ch >= 32 and ch < 127) {
                            field.insert(ch);
                        }
                    }
                } else if (key.codepoint >= 32 and key.codepoint < 127) {
                    field.insert(@intCast(key.codepoint));
                }

                if (old_len != field.len or key.codepoint == vaxis.Key.backspace or key.codepoint == vaxis.Key.delete) {
                    self.updateAllFields(self.focused_field);
                }
                ctx.redraw = true;
            },
            else => {},
        }
    }

    fn typeErasedDrawFn(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *App = @ptrCast(@alignCast(ptr));
        self.clearStatusIfExpired();
        self.updateBlink();
        
        const max_size = ctx.max.size();
        const arena = ctx.arena;

        var surface = vxfw.Surface{
            .size = max_size,
            .widget = self.widget(),
            .buffer = try arena.alloc(Cell, max_size.width * max_size.height),
            .children = &.{},
        };

        // Fill background
        const bg_style: Style = .{ .bg = panel_bg };
        for (surface.buffer) |*cell| {
            cell.* = .{ .style = bg_style, .char = .{ .grapheme = " " } };
        }

        // Minimum terminal size guard
        if (max_size.width < 40 or max_size.height < 12) {
            const msg = " Terminal too small ";
            drawTextAt(&surface, msg, @divFloor(max_size.width, 2) -| 10, @divFloor(max_size.height, 2), .{
                .fg = error_color,
                .bold = true,
            });
            return surface;
        }

        // ─── Header ───────────────────────────────────────────────────────
        const title = " BaseConvert Pro ";
        const subtitle = " Real-time Multi-Base Converter ";
        
        const title_col = @divFloor(max_size.width - title.len, 2);
        drawTextAt(&surface, title, title_col, 1, .{
            .fg = accent_color,
            .bg = header_bg,
            .bold = true,
        });
        drawTextAt(&surface, subtitle, @divFloor(max_size.width - subtitle.len, 2), 2, .{
            .fg = dim_text,
            .bg = header_bg,
        });

        // Separator line
        const sep_y = 4;
        for (0..max_size.width) |col| {
            const idx = sep_y * max_size.width + col;
            if (idx < surface.buffer.len) {
                surface.buffer[idx] = .{
                    .style = .{ .fg = dim_text },
                    .char = .{ .grapheme = "─" },
                };
            }
        }

        // ─── Main Content ─────────────────────────────────────────────────
        const content_start_y = 6;
        const field_width = @min(58, max_size.width - 6);
        const field_height = 3;
        const label_col = @divFloor(max_size.width - field_width, 2);
        const min_draw_height = @min(max_size.height, 3);
        
        // Standard base fields
        for (0..4) |i| {
            const y = content_start_y + i * 5;
            if (y + field_height >= max_size.height -| min_draw_height) break;

            const is_focused = self.focused_field == i;
            
            // Label
            const label = try std.fmt.allocPrint(arena, " {s} (base {d}) ", .{ base_configs[i].name, base_configs[i].base });
            drawTextAt(&surface, label, label_col, y, .{
                .fg = if (is_focused) focused_border else dim_text,
                .bold = is_focused,
            });

            // Field box
            drawFieldBox(&surface, label_col, y + 1, field_width, field_height, is_focused);

            // Text content
            const field = &self.inputs[i];
            const text = field.text();
            const max_text_width = field_width -| 4;
            
            if (text.len > 0) {
                const visible_text = if (text.len > max_text_width) text[0..max_text_width] else text;
                drawTextAt(&surface, visible_text, label_col + 2, y + 2, .{
                    .fg = text_color,
                    .bg = field_bg,
                });
                if (text.len > max_text_width) {
                    drawTextAt(&surface, "…", label_col + 2 + max_text_width - 1, y + 2, .{
                        .fg = dim_text,
                        .bg = field_bg,
                    });
                }
                
                // Cursor
                if (is_focused and self.blink_visible and field.cursor < max_text_width) {
                    const cursor_idx = (y + 2) * max_size.width + (label_col + 2 + field.cursor);
                    if (cursor_idx < surface.buffer.len) {
                        surface.buffer[cursor_idx] = .{
                            .style = .{
                                .fg = .{ .rgb = .{ 0x1E, 0x1E, 0x2E } },
                                .bg = focused_border,
                            },
                            .char = if (field.cursor < text.len) .{ .grapheme = asciiGrapheme(text[field.cursor]) } else .{ .grapheme = " " },
                        };
                    }
                }
            } else {
                const placeholder = try std.fmt.allocPrint(arena, "Enter {s}...", .{base_configs[i].name});
                const visible_placeholder = if (placeholder.len > max_text_width) placeholder[0..max_text_width] else placeholder;
                drawTextAt(&surface, visible_placeholder, label_col + 2, y + 2, .{
                    .fg = dim_text,
                    .bg = field_bg,
                });
                
                if (is_focused and self.blink_visible) {
                    const cursor_idx = (y + 2) * max_size.width + (label_col + 2);
                    if (cursor_idx < surface.buffer.len) {
                        surface.buffer[cursor_idx] = .{
                            .style = .{ .bg = focused_border, .fg = panel_bg },
                            .char = .{ .grapheme = " " },
                        };
                    }
                }
            }

            // Prefix hint
            if (text.len > 0) {
                const hint = try std.fmt.allocPrint(arena, " {s} ", .{base_configs[i].prefix});
                drawTextAt(&surface, hint, label_col + field_width - hint.len - 1, y, .{
                    .fg = dim_text,
                    .bg = panel_bg,
                });
            }
        }

        // ─── Custom Base Section ──────────────────────────────────────────
        const custom_y = content_start_y + 4 * 5 + 1;
        if (custom_y + 5 < max_size.height -| 3) {
            const custom_sep = custom_y;
            for (0..max_size.width) |col| {
                const idx = custom_sep * max_size.width + col;
                if (idx < surface.buffer.len) {
                    surface.buffer[idx] = .{
                        .style = .{ .fg = dim_text },
                        .char = .{ .grapheme = "─" },
                    };
                }
            }

            // Custom base input
            const cb_y = custom_y + 2;
            const is_cb_focused = self.focused_field == 5;
            
            const cb_label = " Custom Base ";
            drawTextAt(&surface, cb_label, label_col, cb_y, .{
                .fg = if (is_cb_focused) focused_border else dim_text,
                .bold = is_cb_focused,
            });
            
            drawFieldBox(&surface, label_col, cb_y + 1, 12, field_height, is_cb_focused);
            const cb_text = self.custom_base_input.text();
            const cb_display = if (cb_text.len > 0) cb_text else "2-36";
            const cb_fg: Color = if (cb_text.len > 0) text_color else dim_text;
            const cb_max_width: usize = 8;
            const cb_visible = if (cb_display.len > cb_max_width) cb_display[0..cb_max_width] else cb_display;
            drawTextAt(&surface, cb_visible, label_col + 2, cb_y + 2, .{
                .fg = cb_fg,
                .bg = field_bg,
            });

            if (is_cb_focused and self.blink_visible and self.custom_base_input.cursor < cb_max_width) {
                const cursor_idx = (cb_y + 2) * max_size.width + (label_col + 2 + self.custom_base_input.cursor);
                if (cursor_idx < surface.buffer.len) {
                    const ch = if (self.custom_base_input.cursor < cb_text.len) cb_text[self.custom_base_input.cursor] else ' ';
                    surface.buffer[cursor_idx] = .{
                        .style = .{ .fg = panel_bg, .bg = focused_border },
                        .char = .{ .grapheme = asciiGrapheme(ch) },
                    };
                }
            }

            // Custom value input
            const cv_y = cb_y;
            const is_cv_focused = self.focused_field == 4;
            const cv_x = label_col + 16;
            
            const cv_label = try std.fmt.allocPrint(arena, " Value (base {d}) ", .{self.custom_base});
            drawTextAt(&surface, cv_label, cv_x, cv_y, .{
                .fg = if (is_cv_focused) focused_border else dim_text,
                .bold = is_cv_focused,
            });
            
            const cv_width = field_width - 16;
            const cv_max_text_width = cv_width -| 4;
            drawFieldBox(&surface, cv_x, cv_y + 1, cv_width, field_height, is_cv_focused);
            const cv_text = self.custom_value_input.text();
            const cv_display = if (cv_text.len > 0) cv_text else "Enter value...";
            const cv_fg: Color = if (cv_text.len > 0) text_color else dim_text;
            const cv_visible = if (cv_display.len > cv_max_text_width) cv_display[0..cv_max_text_width] else cv_display;
            
            drawTextAt(&surface, cv_visible, cv_x + 2, cv_y + 2, .{
                .fg = cv_fg,
                .bg = field_bg,
            });
            if (cv_text.len > cv_max_text_width) {
                drawTextAt(&surface, "…", cv_x + 2 + cv_max_text_width - 1, cv_y + 2, .{
                    .fg = dim_text,
                    .bg = field_bg,
                });
            }

            if (is_cv_focused and self.blink_visible and self.custom_value_input.cursor < cv_max_text_width) {
                const cursor_idx = (cv_y + 2) * max_size.width + (cv_x + 2 + self.custom_value_input.cursor);
                if (cursor_idx < surface.buffer.len) {
                    const ch = if (self.custom_value_input.cursor < cv_text.len) cv_text[self.custom_value_input.cursor] else ' ';
                    surface.buffer[cursor_idx] = .{
                        .style = .{ .fg = panel_bg, .bg = focused_border },
                        .char = .{ .grapheme = asciiGrapheme(ch) },
                    };
                }
            }
        }

        // ─── Value Info Panel ─────────────────────────────────────────────
        const info_y = custom_y + 5;
        if (info_y + 4 < max_size.height -| 3 and info_y > custom_y) {
            const info_sep = info_y;
            for (0..max_size.width) |col| {
                const idx = info_sep * max_size.width + col;
                if (idx < surface.buffer.len) {
                    surface.buffer[idx] = .{
                        .style = .{ .fg = dim_text },
                        .char = .{ .grapheme = "─" },
                    };
                }
            }

            // Try to get the current decimal value for info display
            const dec_text = self.inputs[2].text();
            if (dec_text.len > 0) {
                if (self.parseValue(dec_text, 10)) |val| {
                    var info_items: usize = 0;
                    
                    // ASCII info
                    if (val <= 127) {
                        const ascii_ch: u8 = @intCast(val);
                        const ascii_str = if (std.ascii.isPrint(ascii_ch))
                            try std.fmt.allocPrint(arena, " ASCII: '{c}' ", .{ascii_ch})
                        else
                            try std.fmt.allocPrint(arena, " ASCII: 0x{X:0>2} ", .{ascii_ch});
                        
                        drawTextAt(&surface, ascii_str, label_col, info_y + 1, .{
                            .fg = highlight_color,
                            .bg = info_bg,
                        });
                        info_items += 1;
                    }

                    // Bit width
                    const bit_width: usize = if (val == 0) 1 else @as(usize, std.math.log2_int(u128, @max(val, 1))) + 1;
                    const bit_str = try std.fmt.allocPrint(arena, " Bits: {d} ", .{bit_width});
                    drawTextAt(&surface, bit_str, label_col + 20, info_y + 1, .{
                        .fg = accent_color,
                        .bg = info_bg,
                    });
                    info_items += 1;

                    // Power of 2 check
                    const is_pow2 = val != 0 and (val & (val - 1)) == 0;
                    if (is_pow2) {
                        const pow = std.math.log2_int(u128, val);
                        const pow_str = try std.fmt.allocPrint(arena, " = 2^{d} ", .{pow});
                        drawTextAt(&surface, pow_str, label_col + 35, info_y + 1, .{
                            .fg = success_color,
                            .bg = info_bg,
                        });
                        info_items += 1;
                    }

                    // Byte representation
                    if (info_items > 0) {
                        var byte_buf: [64]u8 = undefined;
                        var stream = std.io.fixedBufferStream(&byte_buf);
                        const writer = stream.writer();
                        _ = writer.write(" Bytes: ") catch {};
                        var i: usize = 0;
                        var v = val;
                        while (v > 0 or i == 0) : (i += 1) {
                            const byte = v & 0xFF;
                            v >>= 8;
                            writer.print("{X:0>2} ", .{byte}) catch break;
                            if (i >= 15) break;
                        }
                        drawTextAt(&surface, stream.getWritten(), label_col, info_y + 2, .{
                            .fg = dim_text,
                            .bg = info_bg,
                        });
                    }
                }
            }
        }

        // ─── History Panel ────────────────────────────────────────────────
        if (self.show_history and max_size.width > 80) {
            const hist_width: usize = 32;
            const hist_x: usize = max_size.width - hist_width - 1;
            const hist_y: usize = content_start_y;
            const available_height: usize = if (max_size.height > hist_y + 4) max_size.height - hist_y - 4 else 0;
            if (available_height >= 5) {
                const hist_height: usize = @min(30, available_height);

                // Background
                const row_end = hist_y + hist_height;
                const col_end = hist_x + hist_width;
                var row: usize = hist_y;
                while (row < row_end) : (row += 1) {
                    var col: usize = hist_x;
                    while (col < col_end) : (col += 1) {
                        const idx = row * max_size.width + col;
                        if (idx < surface.buffer.len) {
                            surface.buffer[idx] = .{
                                .style = .{ .bg = history_bg },
                                .char = .{ .grapheme = " " },
                            };
                        }
                    }
                }

                // Border
                drawBox(&surface, hist_x, hist_y, hist_width, hist_height, .{ .fg = dim_text });
                
                // Title
                const hist_title = " History ";
                drawTextAt(&surface, hist_title, hist_x + @divFloor(hist_width - hist_title.len, 2), hist_y, .{
                    .fg = accent_color,
                    .bold = true,
                    .bg = history_bg,
                });

                // Entries
                var entry_row: usize = hist_y + 2;
                const max_entries = if (hist_height > 4) hist_height - 4 else 0;
                const start_idx = if (self.history.items.len > max_entries) 
                    self.history.items.len - max_entries
                else 
                    0;
            
                for (self.history.items[start_idx..], 0..) |entry, idx| {
                    if (entry_row >= hist_y + hist_height - 1) break;
                    
                    const entry_label = try std.fmt.allocPrint(arena, "{d}. base {d}: ", .{ 
                        start_idx + idx + 1, 
                        entry.base 
                    });
                    drawTextAt(&surface, entry_label, hist_x + 1, entry_row, .{
                        .fg = dim_text,
                        .bg = history_bg,
                    });
                    
                    const value_x = hist_x + 1 + entry_label.len;
                    const max_val_len = hist_width - entry_label.len - 2;
                    const val_display = if (entry.input.len > max_val_len) 
                        try std.fmt.allocPrint(arena, "{s}...", .{entry.input[0..max_val_len]})
                    else 
                        entry.input;
                    
                    drawTextAt(&surface, val_display, value_x, entry_row, .{
                        .fg = text_color,
                        .bg = history_bg,
                    });
                    
                    entry_row += 1;
                }
            }
        }

        // ─── Footer ───────────────────────────────────────────────────────
        const footer_y = max_size.height -| 2;
        if (footer_y < max_size.height and footer_y > 0) {
            for (0..max_size.width) |col| {
                const idx = footer_y * max_size.width + col;
                if (idx < surface.buffer.len) {
                    surface.buffer[idx] = .{
                        .style = .{ .bg = header_bg },
                        .char = .{ .grapheme = " " },
                    };
                }
            }

            const help_text = if (self.status_msg) |msg|
                try std.fmt.allocPrint(arena, " {s} ", .{msg})
            else
                " ↑↓ Tab navigate | Ctrl+C copy | Ctrl+H history | Ctrl+X clear | Ctrl+Q quit ";
            
            const help_fg = if (self.status_msg) |_| success_color else dim_text;
            drawTextAt(&surface, help_text, @divFloor(max_size.width - help_text.len, 2), footer_y, .{
                .fg = help_fg,
                .bg = header_bg,
            });
        }

        return surface;
    }
};

// ─── Drawing Helpers ───────────────────────────────────────────────────────

fn drawTextAt(surface: *vxfw.Surface, text: []const u8, col: usize, row: usize, style: Style) void {
    if (row >= surface.size.height) return;
    for (text, 0..) |byte, i| {
        const c = col + i;
        if (c >= surface.size.width) break;
        const idx = row * surface.size.width + c;
        if (idx < surface.buffer.len) {
            surface.buffer[idx] = .{
                .style = style,
                .char = .{ .grapheme = asciiGrapheme(byte) },
            };
        }
    }
}

fn drawFieldBox(surface: *vxfw.Surface, x: usize, y: usize, width: usize, height: usize, focused: bool) void {
    const border_style: Style = .{
        .fg = if (focused) focused_border else dim_text,
        .bg = field_bg,
    };
    
    for (0..width) |col| {
        const top_idx = y * surface.size.width + (x + col);
        const bot_idx = (y + height - 1) * surface.size.width + (x + col);
        if (top_idx < surface.buffer.len) {
            surface.buffer[top_idx] = .{
                .style = border_style,
                .char = .{ .grapheme = "─" },
            };
        }
        if (bot_idx < surface.buffer.len) {
            surface.buffer[bot_idx] = .{
                .style = border_style,
                .char = .{ .grapheme = "─" },
            };
        }
    }
    
    for (1..height - 1) |row| {
        const left_idx = (y + row) * surface.size.width + x;
        const right_idx = (y + row) * surface.size.width + (x + width - 1);
        if (left_idx < surface.buffer.len) {
            surface.buffer[left_idx] = .{
                .style = border_style,
                .char = .{ .grapheme = "│" },
            };
        }
        if (right_idx < surface.buffer.len) {
            surface.buffer[right_idx] = .{
                .style = border_style,
                .char = .{ .grapheme = "│" },
            };
        }
        
        for (1..width - 1) |col| {
            const fill_idx = (y + row) * surface.size.width + (x + col);
            if (fill_idx < surface.buffer.len) {
                surface.buffer[fill_idx] = .{
                    .style = .{ .bg = field_bg },
                    .char = .{ .grapheme = " " },
                };
            }
        }
    }
    
    const corners = [_][]const u8{ "┌", "┐", "└", "┘" };
    const corner_positions = [_]struct { usize, usize }{
        .{ x, y },
        .{ x + width - 1, y },
        .{ x, y + height - 1 },
        .{ x + width - 1, y + height - 1 },
    };
    
    for (corners, corner_positions) |corner, pos| {
        const idx = pos[1] * surface.size.width + pos[0];
        if (idx < surface.buffer.len) {
            surface.buffer[idx] = .{
                .style = border_style,
                .char = .{ .grapheme = corner },
            };
        }
    }
}

fn drawBox(surface: *vxfw.Surface, x: usize, y: usize, width: usize, height: usize, style: Style) void {
    for (0..width) |col| {
        const top_idx = y * surface.size.width + (x + col);
        const bot_idx = (y + height - 1) * surface.size.width + (x + col);
        if (top_idx < surface.buffer.len) {
            surface.buffer[top_idx] = .{ .style = style, .char = .{ .grapheme = "─" } };
        }
        if (bot_idx < surface.buffer.len) {
            surface.buffer[bot_idx] = .{ .style = style, .char = .{ .grapheme = "─" } };
        }
    }
    
    for (1..height - 1) |row| {
        const left_idx = (y + row) * surface.size.width + x;
        const right_idx = (y + row) * surface.size.width + (x + width - 1);
        if (left_idx < surface.buffer.len) {
            surface.buffer[left_idx] = .{ .style = style, .char = .{ .grapheme = "│" } };
        }
        if (right_idx < surface.buffer.len) {
            surface.buffer[right_idx] = .{ .style = style, .char = .{ .grapheme = "│" } };
        }
    }
    
    const corners = [_][]const u8{ "┌", "┐", "└", "┘" };
    const positions = [_]struct { usize, usize }{
        .{ x, y }, .{ x + width - 1, y },
        .{ x, y + height - 1 }, .{ x + width - 1, y + height - 1 },
    };
    for (corners, positions) |c, p| {
        const idx = p[1] * surface.size.width + p[0];
        if (idx < surface.buffer.len) {
            surface.buffer[idx] = .{ .style = style, .char = .{ .grapheme = c } };
        }
    }
}

// ─── Main ──────────────────────────────────────────────────────────────────

pub fn main() !void {
    var app: App = undefined;
    try app.init();
    defer app.deinit();

    var vaxis_app = try vxfw.App.init(app.allocator());
    defer vaxis_app.deinit();

    try vaxis_app.run(app.widget(), .{});
}
