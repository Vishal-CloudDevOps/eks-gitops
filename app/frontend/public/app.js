const API_BASE = '/api/tasks';

const form = document.getElementById('task-form');
const input = document.getElementById('task-title');
const list = document.getElementById('task-list');
const status = document.getElementById('status');

async function loadTasks() {
  status.textContent = 'Loading...';
  try {
    const res = await fetch(API_BASE);
    if (!res.ok) throw new Error('Request failed');
    const tasks = await res.json();
    renderTasks(tasks);
    status.textContent = `${tasks.length} task(s)`;
  } catch (err) {
    status.textContent = 'Could not reach the backend API.';
    console.error(err);
  }
}

function renderTasks(tasks) {
  list.innerHTML = '';
  tasks.forEach((task) => {
    const li = document.createElement('li');

    const span = document.createElement('span');
    span.textContent = task.title;

    const btn = document.createElement('button');
    btn.textContent = 'Delete';
    btn.className = 'delete-btn';
    btn.onclick = () => deleteTask(task.id);

    li.appendChild(span);
    li.appendChild(btn);
    list.appendChild(li);
  });
}

async function deleteTask(id) {
  await fetch(`${API_BASE}/${id}`, { method: 'DELETE' });
  loadTasks();
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const title = input.value.trim();
  if (!title) return;

  await fetch(API_BASE, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title }),
  });

  input.value = '';
  loadTasks();
});

loadTasks();
