let cachedLogoBase64 = null

/**
 * Loads the official Peñaranda Band 1870 crest logo from /band1870logo.jpg as base64 JPEG
 */
export const getBandLogoBase64 = () => {
  if (cachedLogoBase64) return Promise.resolve(cachedLogoBase64)
  return new Promise((resolve) => {
    if (typeof window === 'undefined' || typeof document === 'undefined') {
      return resolve(null)
    }
    const img = new Image()
    img.crossOrigin = 'Anonymous'
    img.onload = () => {
      try {
        const canvas = document.createElement('canvas')
        canvas.width = img.naturalWidth || img.width
        canvas.height = img.naturalHeight || img.height
        const ctx = canvas.getContext('2d')
        ctx.fillStyle = '#ffffff'
        ctx.fillRect(0, 0, canvas.width, canvas.height)
        ctx.drawImage(img, 0, 0)
        cachedLogoBase64 = canvas.toDataURL('image/jpeg', 0.95)
        resolve(cachedLogoBase64)
      } catch (e) {
        console.warn('Could not rasterize logo for PDF:', e)
        resolve(null)
      }
    }
    img.onerror = () => resolve(null)
    img.src = '/band1870logo.jpg'
  })
}

/**
 * Downloads a blob as a file in the browser
 */
export const triggerPdfDownload = (doc, filename) => {
  const pdfBlob = new Blob([doc.output('blob')], { type: 'application/pdf' })
  const blobUrl = URL.createObjectURL(pdfBlob)

  const downloadLink = document.createElement('a')
  downloadLink.href = blobUrl
  downloadLink.download = filename
  downloadLink.target = '_self'
  downloadLink.style.display = 'none'

  document.body.appendChild(downloadLink)
  downloadLink.click()

  setTimeout(() => {
    if (document.body.contains(downloadLink)) {
      document.body.removeChild(downloadLink)
    }
    URL.revokeObjectURL(blobUrl)
  }, 2000)
}

/**
 * Generates an official, minimal, pure-white PDF Attendance Roll-Call Sheet for a specific event
 */
export const generateEventAttendancePdf = async ({ event, roster, preparedByName = 'Band Secretary' }) => {
  const [jsPDFModule, autoTableModule] = await Promise.all([
    import('jspdf'),
    import('jspdf-autotable')
  ])
  const jsPDF = jsPDFModule.default || jsPDFModule.jsPDF || jsPDFModule
  const autoTable = autoTableModule.default || autoTableModule

  const doc = new jsPDF({
    orientation: 'portrait',
    unit: 'pt',
    format: 'a4'
  })

  const pageWidth = doc.internal.pageSize.getWidth()
  const pageHeight = doc.internal.pageSize.getHeight()

  // 1. Official Header with Peñaranda Band 1870 Logo
  const logoBase64 = await getBandLogoBase64()
  if (logoBase64) {
    try {
      doc.addImage(logoBase64, 'JPEG', 40, 26, 42, 48)
    } catch (e) {
      console.warn('Logo embed error:', e)
    }
  }

  const headerLeft = logoBase64 ? 94 : 40
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(14)
  doc.setTextColor(15, 23, 42)
  doc.text('PEÑARANDA MARCHING BAND 1870', headerLeft, 42)

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8.5)
  doc.setTextColor(100, 116, 139)
  doc.text('Peñaranda, Nueva Ecija • Established 1870 • Municipal Music Unit', headerLeft, 55)
  doc.text('Official Event Attendance Roll-Call & Turnout Verification Sheet', headerLeft, 67)

  // Divider Line
  doc.setDrawColor(203, 213, 225)
  doc.setLineWidth(1)
  doc.line(40, 82, pageWidth - 40, 82)

  // 2. Event Information Banner (Minimal White Box with Hairline Border)
  const bannerY = 94
  doc.setFillColor(255, 255, 255)
  doc.setDrawColor(226, 232, 240)
  doc.setLineWidth(0.75)
  doc.roundedRect(40, bannerY, pageWidth - 80, 50, 4, 4, 'FD')

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(11)
  doc.setTextColor(15, 23, 42)
  doc.text(event?.title || 'Band Gig / Event', 50, bannerY + 18)

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(8)
  doc.setTextColor(71, 85, 105)
  
  const eventDateStr = event?.date || (event?.event_date ? new Date(event.event_date).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' }) : 'Scheduled Date')
  const eventTimeStr = event?.time || (event?.event_date ? new Date(event.event_date).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }) : '')
  const eventTypeStr = event?.type || event?.event_type || 'Rehearsal / Gig'
  const locationStr = event?.location || 'Municipal Bandstand'

  doc.text(`Category: ${eventTypeStr}   |   Schedule: ${eventDateStr} ${eventTimeStr ? `at ${eventTimeStr}` : ''}`, 50, bannerY + 32)
  doc.text(`Location: ${locationStr}`, 50, bannerY + 43)

  // 3. Turnout Tally Summary
  const presentMembers = roster.filter(m => m.currentStatus === 'present')
  const absentMembers = roster.filter(m => m.currentStatus === 'absent')
  const excusedMembers = roster.filter(m => m.currentStatus === 'excused' || m.initialRsvp === 'declined')
  const unconfirmedMembers = roster.filter(m => !m.currentStatus || (m.currentStatus !== 'present' && m.currentStatus !== 'absent' && m.currentStatus !== 'excused' && m.initialRsvp !== 'declined'))

  const tallyY = 152
  doc.setFillColor(250, 250, 250)
  doc.setDrawColor(203, 213, 225)
  doc.setLineWidth(0.5)
  doc.roundedRect(40, tallyY, pageWidth - 80, 22, 3, 3, 'FD')

  doc.setFont('helvetica', 'bold')
  doc.setFontSize(8)
  doc.setTextColor(15, 23, 42)
  doc.text('TURNOUT TALLY:', 48, tallyY + 14)

  doc.setFont('helvetica', 'normal')
  doc.setTextColor(5, 150, 105) // Emerald
  doc.text(`Present: ${presentMembers.length}`, 145, tallyY + 14)

  doc.setTextColor(225, 29, 72) // Rose
  doc.text(`Absent (No-Show): ${absentMembers.length}`, 220, tallyY + 14)

  doc.setTextColor(217, 119, 6) // Amber
  doc.text(`Unavailable / Excused: ${excusedMembers.length}`, 330, tallyY + 14)

  doc.setTextColor(100, 116, 139) // Slate
  doc.text(`Total Musicians: ${roster.length}`, pageWidth - 48, tallyY + 14, { align: 'right' })

  // 4. Sorted Table Rows (Present first, Excused, Absent, Unconfirmed)
  const statusWeight = (m) => {
    if (m.currentStatus === 'present') return 1
    if (m.currentStatus === 'excused' || m.initialRsvp === 'declined') return 2
    if (m.currentStatus === 'absent') return 3
    return 4
  }

  const sortedRoster = [...roster].sort((a, b) => {
    const weightDiff = statusWeight(a) - statusWeight(b)
    if (weightDiff !== 0) return weightDiff
    return (a.name || '').localeCompare(b.name || '')
  })

  const tableRows = sortedRoster.map((m, idx) => {
    let statusLabel = 'Unconfirmed'
    if (m.currentStatus === 'present') statusLabel = 'Present (Attended)'
    else if (m.currentStatus === 'absent') statusLabel = 'Absent (No-Show)'
    else if (m.currentStatus === 'excused') statusLabel = 'Excused'
    else if (m.initialRsvp === 'declined') statusLabel = 'Unavailable (Declined)'
    else if (m.initialRsvp === 'attending') statusLabel = 'RSVP Attending (Pending)'

    let rsvpNote = 'No Response'
    if (m.initialRsvp === 'attending') rsvpNote = 'Committed (Will Attend)'
    else if (m.initialRsvp === 'declined') rsvpNote = 'Declined'

    return [
      idx + 1,
      m.name || 'Musician',
      m.instrument || 'Clarinet',
      m.rank || 'Junior',
      statusLabel,
      rsvpNote
    ]
  })

  // 5. Minimal, Pure White Data Table
  autoTable(doc, {
    startY: 182,
    head: [['#', 'Musician Name', 'Section / Instrument', 'Rank', 'Attendance Status', 'RSVP Record']],
    body: tableRows.length > 0 ? tableRows : [['-', 'No musicians on roll-call roster', '', '', '', '']],
    theme: 'plain',
    headStyles: {
      fillColor: [248, 250, 252],
      textColor: [15, 23, 42],
      fontStyle: 'bold',
      fontSize: 8.5,
      lineColor: [203, 213, 225],
      lineWidth: 0.75,
      halign: 'left'
    },
    styles: {
      font: 'helvetica',
      fontSize: 8,
      textColor: [30, 41, 59],
      fillColor: [255, 255, 255], // Pure white rows, NO alternating gray
      lineColor: [226, 232, 240], // Light minimal border lines
      lineWidth: 0.5,
      cellPadding: 5.5
    },
    alternateRowStyles: {
      fillColor: [255, 255, 255] // PURE WHITE
    },
    columnStyles: {
      0: { halign: 'center', cellWidth: 26 },
      1: { cellWidth: 140 },
      2: { cellWidth: 100 },
      3: { cellWidth: 50 },
      4: { cellWidth: 110 },
      5: { cellWidth: 90 }
    },
    margin: { left: 40, right: 40 },
    didDrawPage: (data) => {
      doc.setFont('helvetica', 'italic')
      doc.setFontSize(7.5)
      doc.setTextColor(148, 163, 184)
      doc.text(
        `Peñaranda Marching Band 1870 — Official Roll-Call Document — Page ${data.pageNumber}`,
        pageWidth / 2,
        pageHeight - 18,
        { align: 'center' }
      )
    }
  })

  // 6. Signatories Block (on the final page)
  const finalY = doc.lastAutoTable.finalY + 32
  if (finalY < pageHeight - 65) {
    doc.setDrawColor(51, 65, 85)
    doc.setLineWidth(0.75)

    const leftX = 130
    const rightX = pageWidth - 130

    doc.line(leftX - 55, finalY, leftX + 55, finalY)
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(8.5)
    doc.setTextColor(15, 23, 42)
    doc.text(preparedByName || 'Band Secretary', leftX, finalY + 11, { align: 'center' })
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(7.5)
    doc.setTextColor(100, 116, 139)
    doc.text('Roll-Call Officer / Secretary', leftX, finalY + 21, { align: 'center' })

    doc.line(rightX - 55, finalY, rightX + 55, finalY)
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(8.5)
    doc.setTextColor(15, 23, 42)
    doc.text('Resident Conductor / President', rightX, finalY + 11, { align: 'center' })
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(7.5)
    doc.setTextColor(100, 116, 139)
    doc.text('Approved by (Peñaranda Band 1870)', rightX, finalY + 21, { align: 'center' })
  }

  // 7. Trigger Direct Download
  const cleanTitle = (event?.title || 'Event')
    .replace(/[^a-zA-Z0-9]/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 30)
  const dateStamp = new Date().toISOString().split('T')[0]
  const filename = `Penaranda_Band_Attendance_${cleanTitle}_${dateStamp}.pdf`

  triggerPdfDownload(doc, filename)
  return filename
}
