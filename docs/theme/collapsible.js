document.addEventListener('DOMContentLoaded', function () {
    const table = document.querySelector('.page-wrapper table');
    if (!table) return;

    const rows = Array.from(table.querySelectorAll('tbody tr'));
    let currentH1 = null;
    let currentH2 = null;

    // First pass: Identify rows and establish hierarchy
    rows.forEach(row => {
        const h1 = row.querySelector('h1');
        const h2 = row.querySelector('h2');
        const h3 = row.querySelector('h3');
        let bwcId;

        if (h1) {
            try { bwcId = 'bwc-' + h1.textContent.match(/BWC \d+/)[0].split(' ')[1]; } catch (e) { return; }
            row.classList.add('bwc-h1', 'collapsible-header');
            row.dataset.bwcId = bwcId;
            currentH1 = bwcId;
            currentH2 = null;
        } else if (h2) {
            try { bwcId = 'bwc-' + h2.textContent.match(/BWC [\d\.]+/)[0].split(' ')[1].replace(/\./g, '-'); } catch (e) { return; }
            row.classList.add('bwc-h2', 'collapsible-header');
            row.dataset.bwcId = bwcId;
            if (currentH1) row.dataset.bwcParent = currentH1;
            currentH2 = bwcId;
        } else if (h3) {
            row.classList.add('bwc-h3', 'collapsible-child');
            if (currentH2) row.dataset.bwcParent = currentH2;
            else if (currentH1) row.dataset.bwcParent = currentH1;
        } else if (row.cells.length > 1 && row.cells[1].textContent.trim() === '') {
            // Handle continuation rows for multi-line descriptions under H3s
            row.classList.add('bwc-h3', 'collapsible-child');
            if (currentH2) row.dataset.bwcParent = currentH2;
            else if (currentH1) row.dataset.bwcParent = currentH1;
        }
    });

    // Second pass: Add icons and set initial state
    const headers = table.querySelectorAll('.collapsible-header');
    headers.forEach(header => {
        // Find the first cell that actually contains the header tag
        const headerCell = header.querySelector('h1, h2, h3')?.parentElement;
        if (headerCell) {
            headerCell.innerHTML = `<span class="toggle-icon">▶</span>` + headerCell.innerHTML;
        }

        // Hide all H2 and H3 rows by default
        if (header.classList.contains('bwc-h2')) {
            header.style.display = 'none';
        }
    });

    table.querySelectorAll('.collapsible-child').forEach(child => {
        child.style.display = 'none';
    });

    // Add the main click listener
    table.addEventListener('click', function (e) {
        const headerRow = e.target.closest('.collapsible-header');
        if (!headerRow) return;

        const bwcId = headerRow.dataset.bwcId;
        const isExpanded = headerRow.classList.contains('expanded');

        // Toggle icon
        const icon = headerRow.querySelector('.toggle-icon');
        if (icon) {
            icon.textContent = isExpanded ? '▶' : '▼';
        }
        headerRow.classList.toggle('expanded');

        // Find and toggle visibility of direct children
        const children = table.querySelectorAll(`[data-bwc-parent="${bwcId}"]`);
        children.forEach(child => {
            if (isExpanded) {
                // Collapse this row and all its descendants
                child.style.display = 'none';
                if (child.classList.contains('expanded')) {
                    child.classList.remove('expanded');
                    const childIcon = child.querySelector('.toggle-icon');
                    if (childIcon) childIcon.textContent = '▶';
                    // Recursively hide grandchildren
                    const grandchildren = table.querySelectorAll(`[data-bwc-parent="${child.dataset.bwcId}"]`);
                    grandchildren.forEach(gc => {
                        gc.style.display = 'none';
                        // Also reset their expanded state if they are headers themselves
                         if (gc.classList.contains('expanded')) {
                            gc.classList.remove('expanded');
                            const gcIcon = gc.querySelector('.toggle-icon');
                            if (gcIcon) gcIcon.textContent = '▶';
                        }
                    });
                }
            } else {
                // Expand this row
                child.style.display = 'table-row';
            }
        });
    });
});