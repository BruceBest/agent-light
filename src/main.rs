use eframe::egui;
use std::fs;
use std::time::Duration;

const STATUS_FILE: &str = "/tmp/claude-traffic-light";

#[derive(Clone, Copy, PartialEq)]
enum Light {
    Red,
    Yellow,
    Green,
}

struct TrafficLightApp {
    current: Light,
}

impl Default for TrafficLightApp {
    fn default() -> Self {
        Self {
            current: Light::Green,
        }
    }
}

impl TrafficLightApp {
    fn read_status(&mut self) {
        if let Ok(content) = fs::read_to_string(STATUS_FILE) {
            self.current = match content.trim() {
                "red" => Light::Red,
                "yellow" => Light::Yellow,
                _ => Light::Green,
            };
        }
    }

    fn draw_light(painter: &egui::Painter, center: egui::Pos2, light: Light, active: bool) {
        let (ar, ag, ab, dr, dg, db) = match light {
            Light::Red => (255u8, 0, 0, 58u8, 0, 0),
            Light::Yellow => (255, 204, 0, 58, 58, 0),
            Light::Green => (0, 204, 0, 0, 58, 0),
        };

        painter.circle_filled(center, 40.0, egui::Color32::from_rgb(dr, dg, db));

        if active {
            for i in (1..=4).rev() {
                let r = 35.0 + (i as f32) * 4.0;
                let alpha = 30 / i as u8;
                painter.circle_filled(
                    center,
                    r,
                    egui::Color32::from_rgba_unmultiplied(ar, ag, ab, alpha),
                );
            }
            painter.circle_filled(center, 35.0, egui::Color32::from_rgb(ar, ag, ab));
            painter.circle_filled(
                egui::pos2(center.x - 10.0, center.y - 10.0),
                12.0,
                egui::Color32::from_rgba_unmultiplied(255, 255, 255, 100),
            );
        } else {
            painter.circle_filled(center, 35.0, egui::Color32::from_rgb(dr, dg, db));
        }
    }

    fn paint(&self, ui: &mut egui::Ui) {
        let rect = ui.available_rect_before_wrap();
        let painter = ui.painter();
        let cx = rect.center().x;

        let body = egui::Rect::from_min_size(
            egui::pos2(cx - 60.0, rect.top() + 10.0),
            egui::vec2(120.0, 350.0),
        );
        painter.rect_filled(body, 20.0, egui::Color32::from_rgb(51, 51, 51));
        painter.rect_stroke(
            body,
            20.0,
            egui::Stroke::new(2.0, egui::Color32::from_rgb(68, 68, 68)),
            egui::StrokeKind::Inside,
        );

        let pole = egui::Rect::from_min_size(
            egui::pos2(cx - 12.0, body.bottom()),
            egui::vec2(24.0, 25.0),
        );
        painter.rect_filled(pole, 4.0, egui::Color32::from_rgb(85, 85, 85));

        let base_y = body.top() + 60.0;
        let spacing = 115.0;
        for (i, light) in [Light::Red, Light::Yellow, Light::Green].iter().enumerate() {
            let y = base_y + spacing * i as f32;
            Self::draw_light(painter, egui::pos2(cx, y), *light, self.current == *light);
        }
    }
}

impl eframe::App for TrafficLightApp {
    fn clear_color(&self, _visuals: &egui::Visuals) -> [f32; 4] {
        [0.0, 0.0, 0.0, 0.0]
    }

    fn ui(&mut self, _ui: &mut egui::Ui, _frame: &mut eframe::Frame) {}

    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.read_status();

        // Drag window on pointer press
        if ctx.input(|i| i.pointer.any_pressed()) {
            ctx.send_viewport_cmd(egui::ViewportCommand::StartDrag);
        }

        #[allow(deprecated)]
        egui::CentralPanel::default()
            .frame(egui::Frame::new().fill(egui::Color32::TRANSPARENT))
            .show(ctx, |ui| {
                self.paint(ui);
            });

        ctx.request_repaint_after(Duration::from_millis(100));
    }
}

fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([160.0, 410.0])
            .with_always_on_top()
            .with_resizable(false)
            .with_decorations(false)
            .with_transparent(true),
        ..Default::default()
    };

    eframe::run_native(
        "Claude Code",
        options,
        Box::new(|_cc| Ok(Box::new(TrafficLightApp::default()))),
    )
}
