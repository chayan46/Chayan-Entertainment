const SPREADSHEET_ID = '11_YGayUIDDDTUGMravPYCOHdZSzJWn7l1RoI4h8XESM';
const MOVIES_SHEET = 'Movies';
const DASHBOARD_SHEET = 'Dashboard';

function doGet() {
  return json_({ ok: true, service: 'Chayan Entertainment Sheets API', version: 1 });
}

function doPost(e) {
  try {
    const payload = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    const action = String(payload.action || '');
    const ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    const sheet = getMoviesSheet_(ss);
    if (action === 'list') {
      return json_({ ok: true, movies: readMovies_(sheet) });
    }
    if (action === 'upsert') {
      const movie = payload.movie || {};
      if (!movie.id || !String(movie.name || '').trim()) throw new Error('Movie ID and title are required.');
      const rows = sheet.getDataRange().getValues();
      let row = -1;
      for (let i = 1; i < rows.length; i++) if (String(rows[i][0]) === String(movie.id)) { row = i + 1; break; }
      const values = [[String(movie.id), String(movie.name).trim(), Number(movie.year) || '', String(movie.category || 'English Movie'), String(movie.posterUrl || ''), new Date()]];
      if (row < 0) sheet.appendRow(values[0]); else sheet.getRange(row, 1, 1, values[0].length).setValues(values);
      formatMovies_(sheet);
      refreshDashboard_(ss, sheet);
      return json_({ ok: true, movie: movie });
    }
    if (action === 'delete') {
      const id = String(payload.id || '');
      const rows = sheet.getDataRange().getValues();
      for (let i = rows.length - 1; i >= 1; i--) if (String(rows[i][0]) === id) sheet.deleteRow(i + 1);
      refreshDashboard_(ss, sheet);
      return json_({ ok: true });
    }
    throw new Error('Unsupported action.');
  } catch (err) {
    return json_({ ok: false, error: String(err && err.message || err) });
  }
}

function getMoviesSheet_(ss) {
  let sh = ss.getSheetByName(MOVIES_SHEET);
  if (!sh) sh = ss.insertSheet(MOVIES_SHEET);
  const headers = ['ID', 'Movie Title', 'Release Year', 'Category', 'Poster URL', 'Updated At'];
  if (sh.getLastRow() === 0) sh.appendRow(headers);
  else sh.getRange(1, 1, 1, headers.length).setValues([headers]);
  formatMovies_(sh);
  return sh;
}

function readMovies_(sh) {
  if (sh.getLastRow() < 2) return [];
  return sh.getRange(2, 1, sh.getLastRow() - 1, 6).getValues().map(r => ({
    id: String(r[0]), name: String(r[1]), year: Number(r[2]) || 0,
    category: String(r[3] || 'English Movie'), posterUrl: String(r[4] || '')
  }));
}

function formatMovies_(sh) {
  sh.setFrozenRows(1);
  sh.getRange(1, 1, 1, 6).setBackground('#202a44').setFontColor('#ffffff').setFontWeight('bold');
  sh.getRange('A:F').setVerticalAlignment('middle');
  sh.setColumnWidth(1, 180); sh.setColumnWidth(2, 260); sh.setColumnWidth(3, 110);
  sh.setColumnWidth(4, 160); sh.setColumnWidth(5, 360); sh.setColumnWidth(6, 180);
  if (sh.getLastRow() > 1) sh.getRange(2, 6, sh.getLastRow() - 1, 1).setNumberFormat('yyyy-mm-dd hh:mm');
}

function refreshDashboard_(ss, sh) {
  let dash = ss.getSheetByName(DASHBOARD_SHEET);
  if (!dash) dash = ss.insertSheet(DASHBOARD_SHEET);
  dash.clear();
  dash.getRange('A1:D1').merge().setValue('CHAYAN ENTERTAINMENT — MOVIE DASHBOARD')
    .setBackground('#202a44').setFontColor('#ffffff').setFontSize(16).setFontWeight('bold');
  dash.getRange('A3:B3').setValues([['LIBRARY METRIC', 'COUNT']])
    .setBackground('#d9e2f3').setFontWeight('bold');
  const rows = readMovies_(sh);
  dash.getRange(4, 1, 4, 2).setValues([
    ['Total Movies', rows.length],
    ['Bengali Movies', rows.filter(m => m.category === 'Bengali Movie').length],
    ['Hindi Movies', rows.filter(m => m.category === 'Hindi Movie').length],
    ['English Movies', rows.filter(m => m.category === 'English Movie').length]
  ]);
  dash.getRange('A10:D10').setValues([['MOVIE TITLE', 'YEAR', 'CATEGORY', 'POSTER']])
    .setBackground('#d9e2f3').setFontWeight('bold');
  const sorted = rows.slice().sort((a,b) => a.name.localeCompare(b.name));
  if (sorted.length) {
    dash.getRange(11, 1, sorted.length, 4).setValues(sorted.map(m => [m.name, m.year, m.category, m.posterUrl]));
    sorted.forEach((m,i) => {
      if (m.posterUrl) {
        try { dash.getRange(11+i, 5).setFormula('=IMAGE("' + m.posterUrl.replace(/"/g, '""') + '",4,100,70)'); } catch (_) {}
      }
    });
  }
  dash.setFrozenRows(3); dash.setColumnWidth(1, 280); dash.setColumnWidth(2, 100);
  dash.setColumnWidth(3, 160); dash.setColumnWidth(4, 340); dash.setColumnWidth(5, 120);
  if (sorted.length) dash.setRowHeights(11, sorted.length, 76);
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
