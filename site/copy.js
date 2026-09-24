// Adds a small copy icon right after each Terminal command. Without this script the command is still selectable with one click.
const SVG = 'http://www.w3.org/2000/svg';
const icons = {
  copy: ['M9 9h9a1.5 1.5 0 0 1 1.5 1.5v9A1.5 1.5 0 0 1 18 21H9a1.5 1.5 0 0 1-1.5-1.5v-9A1.5 1.5 0 0 1 9 9Z', 'M15 9V6A1.5 1.5 0 0 0 13.5 4.5h-9A1.5 1.5 0 0 0 3 6v9a1.5 1.5 0 0 0 1.5 1.5H7.5'],
  done: ['M5 12.5l4.5 4.5L19 7.5'],
};
function icon(name) {
  const svg = document.createElementNS(SVG, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('aria-hidden', 'true');
  for (const d of icons[name]) {
    const path = document.createElementNS(SVG, 'path');
    path.setAttribute('d', d);
    svg.append(path);
  }
  return svg;
}
document.querySelectorAll('.command').forEach((row) => {
  const code = row.querySelector('code');
  if (!code) return;
  const command = code.textContent.trim();
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'copy';
  button.title = 'Kopiera';
  button.setAttribute('aria-label', 'Kopiera kommandot ' + command);
  button.append(icon('copy'));
  const status = document.createElement('span');
  status.className = 'visually-hidden';
  status.setAttribute('aria-live', 'polite');
  let reset;
  const show = (name, title, message) => {
    button.replaceChildren(icon(name));
    button.title = title;
    button.classList.toggle('is-done', name === 'done');
    status.textContent = message;
  };
  button.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(command);
      show('done', 'Kopierat', 'Kommandot är kopierat.');
    } catch {
      const range = document.createRange();
      range.selectNodeContents(code);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      show('copy', 'Markerat – tryck ⌘C', 'Kommandot är markerat. Tryck Kommando C för att kopiera.');
    }
    clearTimeout(reset);
    reset = setTimeout(() => show('copy', 'Kopiera', ''), 1800);
  });
  const wrap = document.createElement('div');
  wrap.className = 'cmd';
  row.before(wrap);
  wrap.append(row, button, status);
});
