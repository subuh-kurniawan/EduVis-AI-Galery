(function () {
    function getSessionSearchText(session) {
        const values = [session?.name || ''];
        const messages = Array.isArray(session?.messages) ? session.messages : [];
        let remaining = 20000;

        for (const message of messages.slice().reverse()) {
            if (!message || typeof message !== 'object' || remaining <= 0) continue;

            for (const key of ['content', 'text', 'prompt', 'message', 'fileName', 'filename']) {
                const value = message[key];
                if (typeof value !== 'string' || !value || value.startsWith('data:')) continue;

                const excerpt = value.slice(0, Math.min(1000, remaining));
                values.push(excerpt);
                remaining -= excerpt.length;
                if (remaining <= 0) break;
            }
        }

        return values.join(' ').toLocaleLowerCase();
    }

    function filterSessions(input) {
        const container = document.getElementById('sessions-list-container');
        if (!container) return;

        const query = input.value.trim().toLocaleLowerCase();
        const items = Array.from(container.querySelectorAll('[data-session-search-item]'));
        let visibleCount = 0;

        for (const item of items) {
            const matches = !query || (item.dataset.searchText || item.textContent)
                .toLocaleLowerCase()
                .includes(query);
            item.hidden = !matches;
            if (matches) visibleCount += 1;
        }

        let emptyMessage = document.getElementById('saved-session-search-empty');
        if (!emptyMessage) {
            emptyMessage = document.createElement('p');
            emptyMessage.id = 'saved-session-search-empty';
            emptyMessage.className = 'text-xs text-slate-400 text-center py-8';
            emptyMessage.setAttribute('role', 'status');
            container.appendChild(emptyMessage);
        }

        const showEmptyMessage = query && items.length > 0 && visibleCount === 0;
        emptyMessage.textContent = `Tidak ada sesi yang cocok dengan "${input.value.trim()}".`;
        emptyMessage.hidden = !showEmptyMessage;
    }

    window.getSavedSessionSearchText = getSessionSearchText;

    document.addEventListener('DOMContentLoaded', () => {
        const input = document.getElementById('saved-session-search');
        const container = document.getElementById('sessions-list-container');
        if (!input || !container) return;
        input.addEventListener('input', () => filterSessions(input));
        new MutationObserver(() => filterSessions(input)).observe(container, { childList: true });
    });
})();
