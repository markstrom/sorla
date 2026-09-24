// Adds a Copy button next to each Terminal command. Without this script the command is still selectable with one click.
document.querySelectorAll('.command').forEach((row) => {
  const code = row.querySelector('code');
  if (!code) return;
  const command = code.textContent.trim();
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'copy';
  button.textContent = 'Kopiera';
  button.setAttribute('aria-label', 'Kopiera kommandot ' + command);
  const status = document.createElement('span');
  status.className = 'visually-hidden';
  status.setAttribute('aria-live', 'polite');
  let reset;
  button.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(command);
      button.textContent = 'Kopierat';
      status.textContent = 'Kommandot är kopierat.';
    } catch {
      const range = document.createRange();
      range.selectNodeContents(code);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      button.textContent = 'Tryck ⌘C';
      status.textContent = 'Kommandot är markerat. Tryck Kommando C för att kopiera.';
    }
    clearTimeout(reset);
    reset = setTimeout(() => { button.textContent = 'Kopiera'; status.textContent = ''; }, 2000);
  });
  const wrap = document.createElement('div');
  wrap.className = 'cmd';
  row.before(wrap);
  wrap.append(row, button, status);
});
