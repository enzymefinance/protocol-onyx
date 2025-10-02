let activeHref = location.href;
function updatePageToc(elem = undefined) {
    let selectedPageTocElem = elem;
    const pagetoc = document.getElementById("pagetoc");

    function getRect(element) {
        return element.getBoundingClientRect();
    }

    // We've not selected a heading to highlight, and the URL needs updating
    // so we need to find a heading based on the URL
    if (selectedPageTocElem === undefined && location.href !== activeHref) {
        activeHref = location.href;
        for (const pageTocElement of pagetoc.children) {
            if (pageTocElement.href === activeHref) {
                selectedPageTocElem = pageTocElement;
            }
        }
    }

    // We still don't have a selected heading, let's try and find the most
    // suitable heading based on the scroll position
    if (selectedPageTocElem === undefined) {
        const margin = window.innerHeight / 3;

        const headers = document.getElementsByClassName("header");
        for (let i = 0; i < headers.length; i++) {
            const header = headers[i];
            if (selectedPageTocElem === undefined && getRect(header).top >= 0) {
                if (getRect(header).top < margin) {
                    selectedPageTocElem = header;
                } else {
                    selectedPageTocElem = headers[Math.max(0, i - 1)];
                }
            }
            // a very long last section's heading is over the screen
            if (selectedPageTocElem === undefined && i === headers.length - 1) {
                selectedPageTocElem = header;
            }
        }
    }

    // Remove the active flag from all pagetoc elements
    for (const pageTocElement of pagetoc.children) {
        pageTocElement.classList.remove("active");
    }

    // If we have a selected heading, set it to active and scroll to it
    if (selectedPageTocElem !== undefined) {
        for (const pageTocElement of pagetoc.children) {
            if (selectedPageTocElem.href.localeCompare(pageTocElement.href) === 0) {
                pageTocElement.classList.add("active");

                // Ensure the active element is visible by scrolling to it when needed
                const pageTocRect = pagetoc.getBoundingClientRect();
                const elementRect = pageTocElement.getBoundingClientRect();

                // Check if element is above the visible area
                if (elementRect.top < pageTocRect.top) {
                    pagetoc.scrollTop += (elementRect.top - pageTocRect.top - 10);
                }
                // Check if element is below the visible area
                else if (elementRect.bottom > pageTocRect.bottom) {
                    pagetoc.scrollTop += (elementRect.bottom - pageTocRect.bottom + 10);
                }
            }
        }
    }
}

if (document.getElementsByClassName("header").length <= 1) {
    // There's one or less headings, we don't need a page table of contents
    document.getElementById("sidetoc").remove();
} else {
    // Populate sidebar on load
    window.addEventListener("load", () => {
        // Function to check if a heading should be excluded from TOC
        function shouldExcludeHeading(header) {
            const headerText = header.textContent || '';
            if (headerText.toLowerCase().includes('table of contents')) {
                return true;
            }
            return false;
        }

        let isFirstHeading = true;
        const headers = document.getElementsByClassName("header");

        for (const header of headers) {
            if (shouldExcludeHeading(header)) {
                continue;
            }

            const link = document.createElement("a");
            link.appendChild(document.createTextNode(header.textContent));
            link.href = header.hash;

            if (isFirstHeading) {
                link.classList.add("pagetoc-title");
                isFirstHeading = false;
            } else {
                link.classList.add("pagetoc-" + header.parentElement.tagName);
            }

            document.getElementById("pagetoc").appendChild(link);

            link.addEventListener('click', (event) => {
                event.preventDefault();

                const targetId = link.hash.substring(1);
                const targetHeader = document.getElementById(targetId);

                if (targetHeader) {
                    let targetRow = targetHeader.closest('tr');

                    const expandParents = (row) => {
                        if (!row) return;
                        const parentId = row.dataset.bwcParent;
                        if (parentId) {
                            const parentRow = document.querySelector(`.collapsible-header[data-bwc-id="${parentId}"]`);
                            if (parentRow) {
                                expandParents(parentRow);
                                if (!parentRow.classList.contains('expanded')) {
                                    parentRow.querySelector('.toggle-icon').click();
                                }
                            }
                        }
                    };

                    expandParents(targetRow);
                }

                setTimeout(() => {
                    if (targetHeader) {
                        targetHeader.scrollIntoView({ behavior: 'smooth', block: 'start' });
                        history.replaceState(null, null, link.hash);
                    }
                    updatePageToc(link);
                }, 100);
            });
        }

        updatePageToc();
    });

    // Update page table of contents selected heading on scroll
    window.addEventListener("scroll", () => updatePageToc());
}

