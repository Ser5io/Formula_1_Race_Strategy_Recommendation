(function () {
  function markActive() {
    var hash = location.hash || "#basics";
    document.querySelectorAll("nav a").forEach(function (link) {
      link.classList.toggle("active", link.getAttribute("href") === hash);
    });
  }
  markActive();
  window.addEventListener("hashchange", markActive);

  var data = window.F1_DATA;
  if (!data) return;
  var summary = data.summary || {};

  document.querySelectorAll("[data-stat]").forEach(function (node) {
    var key = node.getAttribute("data-stat");
    var value = summary[key];
    if (value === undefined || value === null) return;
    node.textContent = Number(value).toLocaleString("en-US");
  });

  renderAudit("bronze", data.bronze_audit, [
    "team_member", "table_name", "row_count", "null_cell_count", "duplicate_key_groups"
  ]);
  renderAudit("silver", data.silver_audit, [
    "team_member", "object_name", "metric", "metric_value"
  ]);
  renderPirelli(data.pirelli_map);
  renderTeams(data.team_colours);
  renderExamples(data.examples || {});
  renderDictionary(data.columns || [], data);

  if (window.Chart) drawCharts(data);
})();

function cell(value) {
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "boolean") return value ? "نعم" : "لا";
  if (typeof value === "number") {
    if (Number.isInteger(value) && Math.abs(value) >= 10000) return value.toLocaleString("en-US");
    return String(value);
  }
  return String(value);
}

function pairTable(rows) {
  return "<table><tbody>" + rows.map(function (row) {
    return "<tr><th>" + row[0] + "</th><td class=\"en\">" + cell(row[1]) + "</td></tr>";
  }).join("") + "</tbody></table>";
}

function renderExamples(examples) {
  var host = document.getElementById("example-host");
  if (!host) return;
  var lap = examples.lap || {};
  var lap1 = examples.lap1 || {};
  var pit = examples.pit_hold || {};
  var drivers = examples.driver_rows || {};
  var lapped = examples.lapped || {};
  var compounds = examples.compounds || {};
  var bronzeDrivers = drivers.bronze || [];
  var silverDriver = drivers.silver || {};

  host.innerHTML = [
    "<article class=\"card\">",
    "<h3>لفة صالحة — " + cell(lap.driver) + " — " + cell(lap.circuit) + " " + cell(lap.year) + " — لفة " + cell(lap.lap_number) + "</h3>",
    "<p>البرونز مخزّن كنص. السيلفر حوّله لأرقام. تصحيح الوقود: <span class=\"en\">" + cell(lap.bronze_lap_duration) + " + 0.03 × 1 = " + cell(lap.silver_fuel) + "</span>.</p>",
    "<div class=\"split\">",
    "<div><h3>Bronze</h3>" + pairTable([
      ["الزمن", lap.bronze_lap_duration],
      ["الوقود في الملف", lap.bronze_fuel],
      ["لفة أولى", lap.bronze_first],
      ["الإطار", lap.bronze_compound]
    ]) + "</div>",
    "<div><h3>Silver</h3>" + pairTable([
      ["الزمن", lap.silver_lap_duration],
      ["بعد تصحيح الوقود", lap.silver_fuel],
      ["وسيط السائق", lap.median],
      ["حد 107%", lap.threshold],
      ["صالحة للاستراتيجية", lap.valid]
    ]) + "</div>",
    "</div>",
    "<p>اللفة مش أولى، وزمنها " + cell(lap.silver_fuel) + " أقل من حد " + cell(lap.threshold) + "، فالعلامة صالحة.</p>",
    "</article>",
    "<article class=\"card\">",
    "<h3>لفة مرفوضة — نفس السباق، لفة " + cell(lap1.lap_number) + "</h3>",
    pairTable([
      ["الزمن الخام", lap1.bronze_lap_duration],
      ["لفة أولى", lap1.is_first],
      ["حالة السباق", lap1.race_condition],
      ["صالحة", lap1.valid]
    ]),
    "<p>اترفضت لأنها اللفة الأولى بعد الإطفاء. الصف لسه موجود.</p>",
    "</article>",
    "<article class=\"card\">",
    "<h3>احتجاز تحت العلم الأحمر</h3>",
    pairTable([
      ["السنة", pit.year],
      ["الحلبة", pit.circuit],
      ["السائق", pit.driver],
      ["اللفة", pit.lap_number],
      ["زمن الوقفة", pit.pit_duration]
    ]),
    "<p>أطول من 60 ثانية، فاتشالت من وقفات السيلفر التكتيكية.</p>",
    "</article>",
    "<article class=\"card\">",
    "<h3>سائق واحد من صفين — فيرستابن 2024</h3>",
    "<div class=\"split\"><div><h3>Bronze</h3>" + pairTable(bronzeDrivers.map(function (row, index) {
      return ["صف " + (index + 1), row.team_colour + " / " + row.races_entered + " سباق"];
    })) + "</div><div><h3>Silver</h3>" + pairTable([
      ["اللون", silverDriver.team_colour],
      ["السباقات", silverDriver.races_entered],
      ["صفوف المصدر", silverDriver.source_row_count]
    ]) + "</div></div>",
    "<p>الفرق بس في حالة الحروف. الصف اللي فيه سباقات أكتر هو اللي فضل.</p>",
    "</article>",
    "<article class=\"card\">",
    "<h3>متأخر بلفة كاملة</h3>",
    pairTable([
      ["السنة", lapped.year],
      ["الحلبة", lapped.circuit],
      ["السائق", lapped.driver],
      ["النص الخام", lapped.gap_raw],
      ["ثواني", lapped.gap_seconds],
      ["لفات تأخير", lapped.laps_down]
    ]),
    "<p>+1 LAP بقت laps_down = 1، والثواني فاضية لأن دي مش فجوة زمنية.</p>",
    "</article>",
    "<article class=\"card\">",
    "<h3>أكواد فاضية بقت C1 و C2 و C3</h3>",
    pairTable([
      ["الحلبة", compounds.circuit + " " + compounds.year],
      ["الهارد في الملف", compounds.bronze_hard],
      ["الميديوم في الملف", compounds.bronze_medium],
      ["السوفت في الملف", compounds.bronze_soft],
      ["بعد التنظيف", [compounds.c_hard, compounds.c_medium, compounds.c_soft].join(" / ")]
    ]),
    "</article>"
  ].join("");
}

function renderDictionary(columns, data) {
  var host = document.getElementById("dictionary-host");
  var dict = window.F1_DICT || { tables: {}, columns: {} };
  if (!host) return;

  var counts = {};
  (data.bronze_audit || []).forEach(function (row) {
    counts["bronze." + row.table_name] = row.row_count;
  });
  (data.silver_audit || []).forEach(function (row) {
    if (row.metric === "silver_rows") counts["silver." + row.object_name] = row.metric_value;
  });

  var grouped = {};
  columns.forEach(function (column) {
    var key = column.schema + "." + column.table_name;
    if (!grouped[key]) grouped[key] = [];
    grouped[key].push(column);
  });

  var order = Object.keys(dict.tables);
  host.innerHTML = order.map(function (key) {
    var meta = dict.tables[key] || {};
    var schema = key.split(".")[0];
    var rows = grouped[key] || [];
    var body = rows.map(function (column) {
      var meaning = dict.columns[column.column_name] || "—";
      var bronzeType = schema === "bronze" ? column.data_type : "—";
      var silverType = schema === "silver" ? column.data_type : "—";
      return "<tr><td class=\"en\">" + column.column_name + "</td><td class=\"en\">" + bronzeType + "</td><td class=\"en\">" + silverType + "</td><td>" + meaning + "</td></tr>";
    }).join("");
    return "<article class=\"card dict-card\" data-schema=\"" + schema + "\">" +
      "<h3 class=\"en\">" + key + "</h3>" +
      "<p>" + (meta.purpose || "") + "</p>" +
      "<p>المسؤول: " + (meta.owner || "—") + " · المفتاح: <span class=\"en\">" + (meta.key || "—") + "</span> · الصفوف: <span class=\"en\">" + cell(counts[key]) + "</span> · بعدها: <span class=\"en\">" + (meta.next || "—") + "</span></p>" +
      "<div class=\"table-wrap\"><table><thead><tr><th>العمود</th><th>نوع Bronze</th><th>نوع Silver</th><th>المعنى</th></tr></thead><tbody>" + body + "</tbody></table></div>" +
      "</article>";
  }).join("");

  document.querySelectorAll(".filter").forEach(function (button) {
    button.addEventListener("click", function () {
      var schema = button.getAttribute("data-schema");
      document.querySelectorAll(".filter").forEach(function (item) {
        item.classList.toggle("active", item === button);
      });
      document.querySelectorAll(".dict-card").forEach(function (card) {
        card.hidden = schema !== "all" && card.getAttribute("data-schema") !== schema;
      });
    });
  });
}

function renderAudit(name, rows, columns) {
  var targets = document.querySelectorAll("[data-audit='" + name + "']");
  if (!targets.length || !rows) return;
  var html = rows.map(function (row) {
    return "<tr>" + columns.map(function (col) {
      var value = row[col];
      if (typeof value === "number" || (typeof value === "string" && value !== "" && !isNaN(value))) {
        value = Number(value).toLocaleString("en-US");
      }
      return "<td class=\"en\">" + (value === null || value === undefined ? "" : value) + "</td>";
    }).join("") + "</tr>";
  }).join("");
  targets.forEach(function (body) { body.innerHTML = html; });
}

function renderPirelli(rows) {
  var body = document.getElementById("pirelli-body");
  if (!body || !rows) return;
  body.innerHTML = rows.map(function (row) {
    return "<tr><td class=\"en\">" + row.year + "</td><td class=\"en\">" + row.round +
      "</td><td>" + row.meeting_name + "</td><td class=\"en\">" + row.circuit +
      "</td><td class=\"en\">" + row.c_hard + "</td><td class=\"en\">" + row.c_medium +
      "</td><td class=\"en\">" + row.c_soft + "</td></tr>";
  }).join("");
}

function renderTeams(rows) {
  var host = document.getElementById("team-badges");
  if (!host || !rows) return;
  var latest = {};
  rows.forEach(function (row) {
    if (!latest[row.team_name] || row.year > latest[row.team_name].year) latest[row.team_name] = row;
  });
  host.innerHTML = Object.keys(latest).sort().map(function (name) {
    var row = latest[name];
    var colour = "#" + String(row.team_colour || "888888").replace("#", "");
    return "<div class=\"card\"><span class=\"team-dot\" style=\"background:" + colour + "\"></span>" +
      name + "<div class=\"en\" style=\"color:#93A0B0\">" + colour + "</div></div>";
  }).join("");
}

function drawCharts(data) {
  Chart.defaults.color = "#C5D0DA";
  Chart.defaults.borderColor = "#243044";
  Chart.defaults.font.family = "Tahoma, sans-serif";

  var years = (data.laps_by_year || []).map(function (row) { return String(row.year); });
  barChart("chart-laps", years, [
    series("كل اللفات", data.laps_by_year, "bronze_laps", "#0066FF"),
    series("صالحة", data.laps_by_year, "valid_laps", "#00F0FF"),
    series("مرفوضة", data.laps_by_year, "rejected_laps", "#FF5C7A")
  ]);

  var reasons = data.rejection_reasons || {};
  barChart("chart-reject", ["اللفة الأولى", "دخول أو خروج بيت", "SC / VSC / أحمر", "أبطأ من 107%", "من غير زمن"], [
    { label: "عدد اللفات", data: [reasons.opening, reasons.pit, reasons.neutralised, reasons.slower_107, reasons.missing_duration], backgroundColor: "#00F0FF" }
  ]);

  compoundChart(data.compound_usage || []);
  degChart(data.compound_usage || []);

  var pits = data.pit_loss || [];
  barChart("chart-pit", pits.map(function (row) { return row.circuit; }), [
    { label: "متوسط خسارة البيت (ثانية)", data: pits.map(num("avg_loss")), backgroundColor: "#0066FF" }
  ], true);

  var flags = data.flags_by_circuit || [];
  barChart("chart-flags", flags.map(function (row) { return row.circuit; }), [
    series("SC", flags, "sc", "#FFFFFF"),
    series("VSC", flags, "vsc", "#00F0FF"),
    series("أحمر", flags, "red", "#FF5C7A")
  ], true);

  var temp = data.bahrain_temp || [];
  lineChart("chart-temp", temp.map(function (row) { return row.observed_at; }), [
    { label: "حرارة التراك", data: temp.map(num("track_temp")), borderColor: "#FF5C7A", tension: 0.2 },
    { label: "حرارة الهواء", data: temp.map(num("air_temp")), borderColor: "#00F0FF", tension: 0.2 }
  ]);

  var drivers = data.drivers_by_year || [];
  barChart("chart-drivers", drivers.map(function (row) { return String(row.year); }), [
    series("قبل الحذف", drivers, "bronze_rows", "#0066FF"),
    series("بعد الحذف", drivers, "silver_rows", "#00F0FF")
  ]);
}

function series(label, rows, key, color) {
  return { label: label, data: (rows || []).map(num(key)), backgroundColor: color };
}

function num(key) {
  return function (row) { return Number(row[key]); };
}

function barChart(id, labels, datasets, horizontal) {
  var canvas = document.getElementById(id);
  if (!canvas) return;
  new Chart(canvas, {
    type: "bar",
    data: { labels: labels, datasets: datasets },
    options: {
      indexAxis: horizontal ? "y" : "x",
      responsive: true,
      maintainAspectRatio: false,
      plugins: { legend: { position: "bottom" } }
    }
  });
}

function lineChart(id, labels, datasets) {
  var canvas = document.getElementById(id);
  if (!canvas) return;
  datasets.forEach(function (set) { set.pointRadius = 0; set.borderWidth = 2; });
  new Chart(canvas, {
    type: "line",
    data: { labels: labels, datasets: datasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: { legend: { position: "bottom" } }
    }
  });
}

function compoundChart(rows) {
  var canvas = document.getElementById("chart-compound");
  if (!canvas) return;
  var years = unique(rows.map(function (row) { return String(row.year); }));
  var compounds = ["SOFT", "MEDIUM", "HARD", "INTERMEDIATE", "WET"];
  var colors = { SOFT: "#E10600", MEDIUM: "#FFD100", HARD: "#F4F4F4", INTERMEDIATE: "#43B02A", WET: "#0077C8" };
  new Chart(canvas, {
    type: "bar",
    data: {
      labels: years,
      datasets: compounds.map(function (compound) {
        return {
          label: compound,
          backgroundColor: colors[compound],
          data: years.map(function (year) {
            var found = rows.find(function (row) { return String(row.year) === year && row.compound === compound; });
            return found ? Number(found.stints) : 0;
          })
        };
      })
    },
    options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { position: "bottom" } } }
  });
}

function degChart(rows) {
  var canvas = document.getElementById("chart-deg");
  if (!canvas) return;
  var dry = rows.filter(function (row) { return row.avg_deg !== null && ["SOFT", "MEDIUM", "HARD"].indexOf(row.compound) >= 0; });
  var years = unique(dry.map(function (row) { return String(row.year); }));
  var colors = { SOFT: "#E10600", MEDIUM: "#FFD100", HARD: "#F4F4F4" };
  new Chart(canvas, {
    type: "bar",
    data: {
      labels: years,
      datasets: ["SOFT", "MEDIUM", "HARD"].map(function (compound) {
        return {
          label: compound,
          backgroundColor: colors[compound],
          data: years.map(function (year) {
            var found = dry.find(function (row) { return String(row.year) === year && row.compound === compound; });
            return found ? Number(found.avg_deg) : 0;
          })
        };
      })
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: { legend: { position: "bottom" } },
      scales: { y: { title: { display: true, text: "ثانية / لفة" } } }
    }
  });
}

function unique(values) {
  return values.filter(function (value, index) { return values.indexOf(value) === index; });
}
