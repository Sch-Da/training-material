---
layout: tutorial_hands_on

title: Using BioImage.IO models for image analysis in Galaxy
zenodo_link: 'https://zenodo.org/record/6647674'
questions:
- How can I apply a pre-trained deep learning model to an image?
- How does the BioImage.IO format integrate with Galaxy?
- What kind of outputs are generated by the model?
objectives:
- Learn how to run a BioImage.IO model using Galaxy
- Understand how to format image inputs and model axes
- Interpret and download the model output
time_estimation: 30M
key_points:
- BioImage.IO models can be run in Galaxy using a dedicated tool
- Input image and model need to be compatible in size and axes
- Galaxy returns both the predicted image and its tensor as output
tags:
- bioimaging
- AI
contributions:
  authorship:
    - dianichj
  editing:
    - kostrykin
---

Deep learning models are increasingly used in bioimage analysis to perform processing steps such as segmentation, classification, and restoration tasks (e.g., {% cite Moen2019 %}). The [BioImage Model Zoo, (BioImage.IO)](https://bioimage.io/#/)({% cite Wei2021 %}) is a repository that provides access to pre-trained AI models, sharing a common metadata model that allows their reuse in different tools and platforms.

Each model in BioImage.IO is tailored for a specific biological task — for example, segmenting nuclei, detecting mitochondria, or identifying neuronal structures — and trained on specific imaging modalities such as electron or fluorescence microscopy (e.g., {% cite vonChamier2021 %}, {% cite GomezdeMariscal2021 %}).

This tutorial will guide you through the process of applying one of these BioImage.IO models to an input image using Galaxy ({% cite Batut2024 %}). You will learn how to upload and configure the model, set the correct input parameters, and interpret the output files.

+⚠️  As of the version {% tool [Process image using a BioImage.IO model](toolshed.g2.bx.psu.edu/repos/bgruening/bioimage_inference/bioimage_inference/2.4.1+galaxy2) %}, only the PyTorch-based BioImage.IO models listed in the section below are compatible with the Galaxy tool.

> <agenda-title></agenda-title>
>
> In this tutorial, we will cover:
>
> 1. TOC
> {:toc}
>
{: .agenda}

## Available BioImage.IO models in Galaxy

| Model name | Task | Imaging modality | Sample / species | Link |
|------------|------|------------------|------------------|------|
| 🪴 PlatynereisEMnucleiSegmentationBoundaryModel | Nuclei segmentation | Electron microscopy | Platynereis | [View model](https://bioimage.io/#/?id=10.5281%2Fzenodo.6028097) |
| 🪴 PlatynereisEMcellsSegmentationBoundaryModel | Cell segmentation | Electron microscopy | Platynereis | [View model](https://bioimage.io/#/?id=10.5281%2Fzenodo.6028280) |
| 🦠 LiveCellSegmentationBoundaryModel | Live cell segmentation | Phase-contrast Microscopy | Various cell types | [View model](https://bioimage.io/#/?id=10.5281%2Fzenodo.5869899) |
| 🔬 HyLFM-Net-stat | Light field reconstruction | Light field and Fluorescence light microscopy | Zebrafish | [View model](https://bioimage.io/#/?tags=HyLFM-Net-stat&id=ambitious-sloth) |
| 🪴 3DUNetArabidopsisApicalStemCells | Stem cell segmentation | Confocal / light sheet | Arabidopsis root | [View model](https://bioimage.io/#/?id=emotional-cricket) |
| 🧬 CovidIFCellSegmentationBoundaryModel | Cell segmentation | Fluorescence light microscopy | Infected human cells | [View model](https://bioimage.io/#/?tags=Covid&id=10.5281%2Fzenodo.5847355) |
| 🧬 NucleiSegmentationBoundaryModel| Nucleus segmentation | Fluorescence light microscopy| Generic / various | [View model](https://bioimage.io/#/?id=10.5281%2Fzenodo.5764892) |
| 🧬 HPANucleusSegmentation | Nucleus segmentation | Immunofluorescence | Human Protein Atlas | [View model](https://bioimage.io/#/?tags=HPA&id=10.5281%2Fzenodo.6200999) |
| 🧠 NeuronSegmentationInEM | Neuron segmentation | Electron microscopy | Brain tissue | [View model](https://bioimage.io/#/?id=10.5281%2Fzenodo.5817052) |
| 🧫 HPACellSegmentationModel | Cell segmentation | Immunofluorescence | Human Protein Atlas | [View model](https://bioimage.io/#/?tags=hpa&id=10.5281%2Fzenodo.6200635) |
| 🧪 MitochondriaEMSegmentationBoundaryModel | Mitochondria segmentation | Electron microscopy | Human | [View model](https://bioimage.io/#/?id=10.5281%2Fzenodo.5874841) |

## Model-specific example

Here we illustrate the type of information that is both useful for understanding the model's biological context and necessary for using the Galaxy tool — specifically, the input axes and input size parameters.

As an example, we consider the following model: **🧬 NucleiSegmentationBoundaryModel**

This model segments nuclei in fluorescence microscopy images. It predicts <em>boundary maps</em> and <em>foreground probabilities</em> for nucleus segmentation, primarily in images stained with DAPI. The outputs are designed to be post-processed with methods such as Multicut or Watershed to achieve instance-level segmentation (object-based segmentation).

- **Imaging modality**: Fluorescence microscopy
- **Task**: Nucleus segmentation (boundary-aware)
- **Input axes**: `bcyx`
- **Input size**: `256,256,1,1`
- **Model link**: [View on BioImage.IO](https://bioimage.io/#/r/ilastik/stardist_dsb_training_data)
- **Citation**: [10.5281/zenodo.5764893](https://doi.org/10.5281/zenodo.5764893)


> <tip-title> Where to find this information on BioImage.IO </tip-title>
>
> You can find similar details for other models directly on [BioImage.IO](https://bioimage.io) by viewing each model’s card. Look under the “inputs” section of the RDF file to find the required `axes` and `input size` values. These parameters are essential for running the model correctly in Galaxy.
>
{: .tip}


## Get data

> <hands-on-title> Data Upload </hands-on-title>
>
> 1. Create a new history for this tutorial.
>
> 2. Download the following image and import it into your Galaxy history.
>    For the purpose of this tutorial, we will use one image to test only one of the 11 available models:
>
>    - [`test_image_nuclei.tiff`](../../images/process-image-bioimageio/input_nucleisegboundarymodel.png)
>
>    If you are importing the image via URL:
>
>    {% snippet faqs/galaxy/datasets_import_via_link.md %}
>
>    If you are importing the image from the shared data library:
>
>    {% snippet faqs/galaxy/datasets_import_from_data_library.md %}
>
> 3. Rename the datasets appropriately if needed (e.g. `"BioImage.IO model"`, `"Test image"`)
>
> 4. Confirm the datatypes are correct (`pt` for the model, `tiff` or `png` for the image)
>
>    {% snippet faqs/galaxy/datasets_change_datatype.md datatype="datatypes" %}
>
> 5. Import the BioImage.IO model from the Galaxy file repository:
>
>    - Click on **Upload Data**
>    - Go to the ** Choose from repository** tab
>    - Navigate to: `ML models` → `bioimaging-models`
>    - Select the desired model file (for this tutorial, choose `nucleisegmentationboundarymodel.pt`)
>    - Click **Import** to add it to your history
>
>    If you are importing the model from the shared data library:
>
>    {% snippet faqs/galaxy/datasets_import_from_data_library.md %}
>
{: .hands_on}


## Run the model on your image

> <hands-on-title> Run BioImage.IO model </hands-on-title>
>
> 1. {% tool [Process image using a BioImage.IO model](toolshed.g2.bx.psu.edu/repos/bgruening/bioimage_inference/bioimage_inference/2.4.1+galaxy1) %} with the following parameters:
>    - {% icon param-file %} *"BioImage.IO model"*: `nucleisegmentationboundarymodel.pt`
>    - {% icon param-file %} *"Input image"*: `test_image_nuclei.png`
>    - {% icon param-text %} *"Size of the input image"*: `256,256,1,1`
>    - {% icon param-select %} *"Axes of the input image"*: `bcyx`
>
>    > <comment-title>Axes and size</comment-title>
>    >
>    > The input **axes** define the order of image dimensions expected by the model:
>    > - `b`: batch
>    > - `c`: channel
>    > - `y`: vertical axis
>    > - `x`: horizontal axis
>    >
>    > The **input size** must match that order.
>    > For example: `256,256,1,1` = 256 px height (`y`), 256 px width (`x`), 1 channel (`c`), and 1 image (`b`).
>    >
>    > This information is provided in the model’s RDF file on [BioImage.IO](https://bioimage.io).
>    {: .comment}
>
{: .hands_on}

The model will process the input image and generate two outputs:
- Two predicted images (written in one TIFF file)
- A predicted tensor matrix (`.npy`)

Below is a visualization of the two predicted images generated by the **🧬 NucleiSegmentationBoundaryModel**.
👉 **See tip below** for how to properly visualize the output.

![Example of tiff output from nuclei segmentation model](../../images/process-image-bioimageio/output-nucleus-seg-model.png "Predicted output – Nucleus Segmentation")

> <tip-title> Visualising the output images</tip-title>
>
> Galaxy provides a basic preview using its `.tiff` visualization tool. However, BioImage.IO models sometimes produce tiff files with several predicted images residing in the same tiff file.
>
> To properly explore the results, it is recommended to click on the **visualize** icon in the output file, this will give you the option to display the dataset using the **Avivator tool**.
> ![Inspect output with Avivator](../../images/process-image-bioimageio/display-avivator.png "Visualize your Tiff output with Avivator in Galaxy")
>
> An alternative is to download the file and open it locally using image analysis tools such as **Fiji/ImageJ**, **napari**, or **QuPath**.
>
{: .tip}

> <question-title> Check your understanding </question-title>
>
> 1. Why do the image axes matter when using a model?
> 2. What happens if the image size does not match the model input?
> 3. What are TIFF and NPY formats?
> 4. How can you interpret the output of the model, and what does it tell you about your input image?
>
> > <solution-title></solution-title>
> >
> > 1. Because deep learning models are trained on specific image shapes and dimensions; mismatches will cause errors or wrong results.
> > 2. The model will fail to run or produce invalid output.
> > 3. **TIFF (.tif)** is a standard format for storing image data, commonly used in microscopy and bioimaging. It can be easily viewed and interpreted visually.
> >    **NPY (.npy)** is a binary format used by NumPy to store arrays. In this case, it contains the raw prediction tensor produced by the model, which can be useful for further analysis or visualization with Python tools.
> > 4. The model generates a **predicted image** that highlights or segments specific structures (e.g. nuclei, cells, mitochondria) based on what it learned during training. By comparing the output image to the input, users can see which regions were detected or classified, helping to extract biological meaning from the raw data.
> >
>{: .solution}
{: .question}


# Conclusion

In this tutorial, you learned how to run a BioImage.IO model on a biological image using Galaxy. By uploading a compatible model and image, setting the appropriate size and axes, and running the tool, you obtained both a predicted image and a tensor matrix representing the model output.

This provides a fast, reproducible way to apply deep learning models in the context of bioimage analysis — all within Galaxy.
